import 'dart:io';
import 'package:cli_spin/cli_spin.dart';
import 'package:hero_common/hero_common.dart';
import 'package:v04/persistence/sqlite3_database_adapter.dart';
import 'package:v04/effects/sound.dart';
import 'package:v04/terminal/prompt.dart';
import 'package:v04/terminal/terminal.dart';

Future<void> main() async {
  // Configure terminal callbacks so hero_common's prompt methods work
  Callbacks.configure(
    promptFor: promptFor,
    promptForYesNo: promptForYesNo,
    promptForYes: promptForYes,
    println: Terminal.println,
    startWaiting: (text) {
      final spinner = CliSpin(
        text: text,
        spinner: CliSpinners.dots,
      ).start();
      return spinner.stop;
    },
    printLnAndRedisplay: Terminal.printLnAndRedisplayCurrentPrompt,
  );

  // Clear screen and set green text
  Terminal.initialize();

  // ASCII art banner
  Terminal.println("\n${AsciiArt.createBanner("HERO MANAGER v04")}\n");

  Terminal.println("Welcome to the Hero Manager!");

  final constantsSet = Runtime.prepareConstantsSet();
  HeroShqlAdapter.registerHeroSchema(constantsSet);
  final runtime = Runtime.prepareRuntime(constantsSet);

  var heroDataManager = HeroDataManager(
    await HeroRepository.create('v04.db', Sqlite3Driver()),
    runtime: runtime,
    constantsSet: constantsSet,
  );

  var doWOrk = true;
  Map<String, (Function, String)> commands = {
    "c": (
      (_) => createHero(heroDataManager),
      "[C]reate a new hero (will prompt for details)",
    ),
    "l": ((_) => listHeroes(heroDataManager), "[L]ist all heroes"),
    "t": (
      (arg) async => await listTopNHeroes(heroDataManager, arg: arg),
      "List [T]op n heroes (will prompt for n)",
    ),
    "s": (
      (arg) async => await listMatchingHeroes(heroDataManager, query: arg),
      "[S]earch matching heroes (will prompt for a search string)",
    ),
    "a": (
      (arg) async => await amendHero(heroDataManager, query: arg),
      "[A]mend a hero (will prompt for details)",
    ),
    "d": (
      (arg) async => await deleteHero(heroDataManager, query: arg),
      "[D]elete one or many heroes (will prompt for a search string)",
    ),
    "e": (
      (_) async => await deleteAllHeroes(heroDataManager),
      "[E]rase database (delete all heroes)",
    ),
    "o": ((_) => goOnline(heroDataManager), "Go [O]nline to download heroes"),
    "q": (
      (_) async => {
        if (await promptQuit()) {doWOrk = false},
      },
      "[Q]uit (exit the program)",
    ),
  };

  Future<void> defaultCommand(String query) async =>
      await listMatchingHeroes(heroDataManager, query: query);

  var prompt = generatePrompt(
    commands,
    defaultAction: " or enter a search string in SHQL™: or plain text,",
  );

  while (doWOrk) {
    try {
      await menu(
        heroDataManager,
        prompt,
        commands,
        defaultCommand: defaultCommand,
        defaultAction: 'performing default search',
      );
    } catch (e) {
      Terminal.println("Unexpected error: $e");
    }

    // allow any pending async operations to complete to save changes
    await Future.delayed(Duration.zero);
  }

  // Properly dispose of resources before exit
  await heroDataManager.dispose();
  Terminal.cleanup();
  await Sound.playExitSound();
  print("Done");
  exit(0);
}

String generatePrompt(
  Map<String, (Function, String)> commands, {
  String defaultAction = '',
}) {
  StringBuffer promptBuffer = StringBuffer();
  promptBuffer.write("""
Enter a menu option (""");
  for (int i = 0; i < commands.length; i++) {
    if (i > 0) {
      if (i == commands.length - 1) {
        promptBuffer.write(" or ");
      } else {
        promptBuffer.write(", ");
      }
    }
    promptBuffer.write(commands.keys.elementAt(i).toUpperCase());
  }
  promptBuffer.writeln(")$defaultAction and press enter:");

  for (var entry in commands.entries) {
    promptBuffer.writeln(entry.value.$2);
  }
  return promptBuffer.toString();
}

Future<void> menu(
  HeroDataManaging heroDataManager,
  String prompt,
  Map<String, (Function, String)> commands, {
  Function(String)? defaultCommand,
  String? defaultAction,
}) async {
  // Wait for all pending operations
  await Future.delayed(Duration(milliseconds: 100));
  var input = await promptFor(prompt);
  if (input.isEmpty) {
    Terminal.println("Please enter a command");
    return;
  }

  var parts = input.split(' ');
  var command = commands[parts[0].trim().toLowerCase()]?.$1;
  var remainder = input.substring(parts[0].length).trim();

  if (command == null) {
    if (defaultCommand != null) {
      Terminal.println("No recognized command entered, $defaultAction");
      await defaultCommand(input);
      return;
    }

    Terminal.println("Invalid command, please try again");
    Terminal.showPrompt(null);
    return;
  }
  await command(remainder.isEmpty ? null : remainder);
}

Future<bool> promptQuit() async {
  Sound.playWarningSound();
  if (!(await promptForYesNo("Do you really want to exit?"))) {
    return false;
  }
  Terminal.println("Exiting...");
  return true;
}

void listHeroes(HeroDataManaging heroDataManager) {
  var heroes = heroDataManager.heroes;
  if (heroes.isEmpty) {
    Terminal.println("No heroes found");
  } else {
    Terminal.println("Found ${heroes.length} heroes:");
    for (var hero in heroes) {
      Terminal.println(hero.toString());
    }
  }
}

Future<void> listTopNHeroes(
  HeroDataManaging heroDataManager, {
  String? arg,
}) async {
  var n =
      int.tryParse(arg ?? await promptFor("Enter number of heroes to list:")) ??
      0;
  if (n <= 0) {
    Terminal.println("Invalid number");
    return;
  }
  var snapshot = heroDataManager.heroes;
  for (int i = 0; i < n; i++) {
    if (i >= snapshot.length) {
      break;
    }
    Terminal.println(snapshot[i].toString());
  }
}

Future<void> listMatchingHeroes(
  HeroDataManaging heroDataManager, {
  String? query,
}) async {
  Sound.playSearchSound();
  var result = await search(heroDataManager, query: query);
  if (result == null) {
    return;
  }
  for (var hero in result) {
    Terminal.println(hero.toString());
  }
}

Future<void> saveHeroes(
  HeroDataManaging heroDataManager, {
  String? query,
}) async {
  query ??= await promptFor("Enter a search string:");
  var heroService = HeroService(await Env.createAsync());
  var onlineSound = Sound.playOnlineSound();
  var timestamp = DateTime.timestamp();
  Terminal.println('''

Online search started at $timestamp

''');

  final spinner = CliSpin(
    text: 'Downloading heroes ...',
    spinner: CliSpinners.dots,
  ).start();

  var results = await heroService.search(query);

  spinner.stop();

  String? error;
  if (results != null) {
    error = results["error"];
  }
  if (error != null) {
    Terminal.println("Failed to search online heroes: $error");
    return;
  }

  if (results == null) {
    Terminal.println("Server returned no data when searching for '$query'");
    return;
  }

  bool saveAll = false;
  var saveCount = 0;
  try {
    var previousHeightConflictResolver = Height.conflictResolver;
    var previousWeightConflictResolver = Weight.conflictResolver;
    SearchResponseModel searchResponseModel;
    try {
      var heightConflictResolver = Height.conflictResolver =
          ManualConflictResolver<Height>();
      var weightConflictResolver = Weight.conflictResolver =
          ManualConflictResolver<Weight>();
      List<String> failures = [];
      searchResponseModel = await SearchResponseModel.fromJson(
        heroDataManager,
        results,
        timestamp,
        failures,
      );

      for (var error in failures) {
        Terminal.println(error);
      }

      for (var error in heightConflictResolver.resolutionLog) {
        Terminal.println(error);
      }
      for (var error in weightConflictResolver.resolutionLog) {
        Terminal.println(error);
      }
    } finally {
      // Restore previous conflict resolvers
      Height.conflictResolver = previousHeightConflictResolver;
      Weight.conflictResolver = previousWeightConflictResolver;
    }

    Terminal.println('''

Found ${searchResponseModel.results.length} heroes online:''');
    for (var hero in searchResponseModel.results) {
      if (heroDataManager.getByExternalId(hero.externalId) != null) {
        Terminal.println(
          'Hero  ${hero.externalId} ("${hero.name}") already exists locally - skipping (run reconciliation to update existing heroes with online data)',
        );
        continue;
      }

      if (!saveAll) {
        var yesNoAll = await promptForYesNoAllQuit(
          '''Save the following hero locally?
$hero''',
        );
        if (yesNoAll == YesNoAllQuit.quit) {
          Terminal.println("Aborting saving of further heroes");
          break;
        }
        if (yesNoAll == YesNoAllQuit.no) {
          continue;
        }
        if (yesNoAll == YesNoAllQuit.all) {
          saveAll = true;
        }
      }
      heroDataManager.persist(hero, action: Sound.playCharacterSavedSound);
      Terminal.println(
        '''Saved hero ${hero.externalId} ("${hero.name}") so it can save you:
$hero''',
      );
      ++saveCount;
    }
  } catch (e) {
    Terminal.println("Failed to parse online heroes: $e");
  }

  onlineSound.then((_) => Sound.playDownloadComplete());

  Terminal.println('''

Download complete at ${DateTime.timestamp()}: $saveCount heroes saved (so they can in turn save ${saveCount * saveCount * 10} people, or more, depending on their abilities).

''');
}

Future<void> deleteAllHeroes(HeroDataManaging heroDataManager) async {
  Sound.playWarningSound();
  if (!(await promptForYesNo("Do you really want to delete all heroes?"))) {
    return;
  }
  heroDataManager.clear();
  Sound.playHeroDeletedSound();
  Terminal.println("Deleted all heroes");
}

void deleteHeroUnprompted(HeroDataManaging heroDataManager, HeroModel hero) {
  heroDataManager.delete(hero);
  Sound.playHeroDeletedSound();
  Terminal.println('''Deleted hero:
$hero''');
}

Future<bool> deleteHeroPrompted(
  HeroDataManaging heroDataManager,
  HeroModel hero,
) async {
  Sound.playWarningSound();
  if (!(await promptForYesNo(
    '''Do you really want to delete hero with the following details?$hero''',
  ))) {
    return false;
  }

  deleteHeroUnprompted(heroDataManager, hero);
  return true;
}

Future<void> deleteHero(
  HeroDataManaging heroDataManager, {
  String? query,
}) async {
  var results = await search(heroDataManager, query: query);
  if (results == null) {
    return;
  }
  bool deleteAll = false;
  for (var hero in results) {
    if (deleteAll) {
      deleteHeroUnprompted(heroDataManager, hero);
      continue;
    }
    if (!deleteAll) {
      var yesNoAllQuit = await promptForYesNoAllQuit('''

Delete the following hero?$hero''');
      switch (yesNoAllQuit) {
        case YesNoAllQuit.yes:
          await deleteHeroPrompted(heroDataManager, hero);
          break;
        case YesNoAllQuit.all:
          deleteAll = true;
          deleteHeroUnprompted(heroDataManager, hero);
        case YesNoAllQuit.no:
          continue;
        case YesNoAllQuit.quit:
          return;
      }
    }
  }
}

Future<void> createHero(HeroDataManaging heroDataManager) async {
  HeroModel? hero = await HeroModel.fromPrompt();
  if (hero == null) {
    Terminal.println("Aborted");
    return;
  }

  if (!(await promptForYesNo(
    '''Save new hero with the following details?$hero''',
  ))) {
    return;
  }

  heroDataManager.persist(hero, action: Sound.playCharacterSavedSound);
  Terminal.println('''Created hero:
$hero''');
}

Future<void> amendHero(
  HeroDataManaging heroDataManager, {
  String? query,
}) async {
  HeroModel? hero = await queryForAction(
    heroDataManager,
    "Amend",
    query: query,
  );
  if (hero == null) {
    return;
  }
  var amededHero = await hero.promptForAmendment();
  if (amededHero != null) {
    heroDataManager.persist(amededHero, action: Sound.playCharacterSavedSound);
    Terminal.println('''Amended hero:
$amededHero''');
  }
}

Future<void> unlockHero(
  HeroDataManaging heroDataManager, {
  String? query,
}) async {
  HeroModel? hero = await queryForAction(
    heroDataManager,
    "Unlock to enable reconciliation",
    query: query,
    filter: (h) => h.locked,
    notFound: "All heroes matching the search term are already unlocked",
  );
  if (hero == null) {
    return;
  }
  var unlockedHero = hero.unlock();

  if (!hero.locked) {
    Terminal.println("Hero is already unlocked");
    return;
  }

  if (unlockedHero.locked) {
    Terminal.println("Hero could not be unlocked");
    return;
  }

  heroDataManager.persist(unlockedHero, action: Sound.playCharacterSavedSound);
  Terminal.println('''Hero was unlocked:
$unlockedHero''');
}

Future<List<HeroModel>?> search(
  HeroDataManaging heroDataManager, {
  String? query,
  bool Function(HeroModel)? filter,
  String? notFound,
}) async {
  query ??= await promptFor("Enter a search string in SHQL™ or plain text:");
  if (query.trim().isEmpty) {
    Terminal.println("Empty search string, operation aborted.");
    return null;
  }
  var results = await heroDataManager.query(query, filter: filter);
  if (results.isEmpty) {
    Terminal.println("${notFound ?? "No heroes found"}\n");
    return null;
  }
  Terminal.println("Found ${results.length} heroes:");
  return results;
}

Future<HeroModel?> queryForAction(
  HeroDataManaging heroDataManager,
  String what, {
  String? query,
  bool Function(HeroModel)? filter,
  String? notFound,
}) async {
  var results = await search(
    heroDataManager,
    query: query,
    filter: filter,
    notFound: notFound,
  );
  if (results == null) {
    return null;
  }
  for (var hero in results) {
    switch (await promptForYesNextCancel('''

$what the following hero?$hero''')) {
      case YesNextCancel.yes:
        return hero;
      case YesNextCancel.next:
        continue;
      case YesNextCancel.cancel:
        return null;
    }
  }
  return null;
}

Future<void> goOnline(HeroDataManaging heroDataManager) async {
  Sound.playMenuSound();
  bool exit = false;
  Map<String, (Function, String)> commands = {
    "r": (
      (_) async => await reconcileHeroes(heroDataManager),
      "[R]econcile local heroes with online updates",
    ),
    "s": (
      (arg) async => await saveHeroes(heroDataManager, query: arg),
      "[S]earch online for new heroes to save",
    ),
    "u": (
      (arg) => unlockHero(heroDataManager, query: arg),
      "[U]nlock manually amended heroes to enable reconciliation",
    ),
    "x": ((_) => {exit = true}, "E[X]it and return to main menu"),
  };

  void defaultCommand(String query) =>
      saveHeroes(heroDataManager, query: query);

  var prompt = generatePrompt(
    commands,
    defaultAction: " or enter an online search string for heroes to save,",
  );

  while (!exit) {
    try {
      await menu(
        heroDataManager,
        prompt,
        commands,
        defaultCommand: defaultCommand,
        defaultAction: 'performing online search',
      );
    } catch (e) {
      Terminal.println("Unexpected error: $e");
    }
  }
  Sound.playMenuSound();
}

Future<void> reconcileHeroes(HeroDataManaging heroDataManager) async {
  Future<void>? startupSequence;
  var timestamp = DateTime.timestamp();
  Terminal.println(''' 

Reconciliation started at at $timestamp

''');
  HeroServicing? heroService;
  bool deleteAll = false;
  bool updateAll = false;
  var deletionCount = 0;
  var reconciliationCount = 0;
  for (var hero in heroDataManager.heroes) {
    startupSequence ??= Sound.playOnlineSound();
    heroService ??= HeroService(await Env.createAsync());
    final spinner = CliSpin(
      text: 'Reconciling hero: ${hero.externalId} ("${hero.name}") ...',
      spinner: CliSpinners.dots,
    ).start();

    var onlineHeroJson = await heroService.getById(hero.externalId);

    spinner.stop();
    String? error;
    if (onlineHeroJson != null) {
      error = onlineHeroJson["error"];
    }

    if (onlineHeroJson == null || error != null) {
      if (hero.locked) {
        Terminal.println(
          '''Hero: ${hero.externalId} ("${hero.name}") does not exist online: "${error ?? 'Unknown error'}" but is locked by prior manual amendment - skipping deletion''',
        );
        continue;
      }

      if (deleteAll) {
        Terminal.println(
          'Hero: ${hero.externalId} ("${hero.name}") does not exist online: "${error ?? 'Unknown error'}" - deleting from local database',
        );
        deleteHeroUnprompted(heroDataManager, hero);
        ++deletionCount;
        continue;
      }

      var yesNoAllQuit = await promptForYesNoAllQuit(
        'Hero: ${hero.externalId} ("${hero.name}") does not exist online: "${error ?? 'Unknown error'}" - delete it from local database?',
      );
      switch (yesNoAllQuit) {
        case YesNoAllQuit.yes:
          if (await deleteHeroPrompted(heroDataManager, hero)) {
            ++deletionCount;
          }
          break;
        case YesNoAllQuit.no:
          // Do nothing
          break;
        case YesNoAllQuit.all:
          deleteAll = true;
          deleteHeroUnprompted(heroDataManager, hero);
          ++deletionCount;
          break;
        case YesNoAllQuit.quit:
          {
            Terminal.println("Aborting reconciliation of further heroes");
            return;
          }
      }
      continue;
    }

    var previousHeightConflictResolver = Height.conflictResolver;
    var previousWeightConflictResolver = Weight.conflictResolver;
    try {
      // Use height and weight conflict resolvers that use the system of units information from the the current hero being amended
      var heightConflictResolver = Height.conflictResolver =
          AutoConflictResolver<Height>(hero.appearance.height.systemOfUnits);
      var weightConflictResolver = Weight.conflictResolver =
          AutoConflictResolver<Weight>(hero.appearance.weight.systemOfUnits);

      HeroModel updatedHero;
      try {
        updatedHero = await hero.apply(onlineHeroJson, timestamp, false);
      } catch (e) {
        Terminal.println(
          'Failed to reconcile hero: ${hero.externalId} ("${hero.name}"): $e',
        );
        continue;
      }

      for (var error in heightConflictResolver.resolutionLog) {
        Terminal.println(error);
      }
      for (var error in weightConflictResolver.resolutionLog) {
        Terminal.println(error);
      }

      var sb = StringBuffer();
      var diff = hero.diff(updatedHero, sb);
      if (!diff) {
        Terminal.println(
          'Hero: ${hero.externalId} ("${hero.name}") is already up to date',
        );
        continue;
      }

      if (hero.locked) {
        Terminal.println(
          '''Hero: ${hero.externalId} ("${hero.name}") is locked by prior manual amendment, skipping reconciliation changes:

${sb.toString()}''',
        );
        continue;
      }

      if (updateAll) {
        heroDataManager.persist(updatedHero, action: Sound.playCharacterSavedSound);
        ++reconciliationCount;
        Terminal.println(
          '''Reconciled hero: ${hero.externalId} ("${hero.name}") with the following online changes:
${sb.toString()}''',
        );
        continue;
      }

      var yesNoAllQuit = await promptForYesNoAllQuit(
        '''Reconcile hero: ${hero.externalId} ("${hero.name}") with the following online changes?
  ${sb.toString()}''',
      );

      switch (yesNoAllQuit) {
        case YesNoAllQuit.yes:
          // continue below
          break;
        case YesNoAllQuit.no:
          // Do nothing
          continue;
        case YesNoAllQuit.all:
          updateAll = true;
          // continue below
          break;
        case YesNoAllQuit.quit:
          {
            Terminal.println("Aborting reconciliation of further heroes");
            return;
          }
      }

      heroDataManager.persist(updatedHero, action: Sound.playCharacterSavedSound);
      ++reconciliationCount;
      Terminal.println(
        '''Reconciled hero: ${hero.externalId} ("${hero.name}") with the following online changes:
${sb.toString()}''',
      );
    } catch (e) {
      Terminal.println(
        'Failed to reconcile hero: ${hero.externalId} ("${hero.name}"): $e',
      );
    } finally {
      Weight.conflictResolver = previousWeightConflictResolver;
      Height.conflictResolver = previousHeightConflictResolver;
    }
  }

  Sound.playReconciliationComplete();
  Terminal.println('''

Reconciliation complete at ${DateTime.timestamp()}: $reconciliationCount heroes reconciled, $deletionCount heroes deleted.

''');
}
