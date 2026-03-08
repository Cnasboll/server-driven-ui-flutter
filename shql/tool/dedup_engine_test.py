"""Remove duplicate shqlBoth/shqlBothStdlib tests from engine_test.dart.
A test is a duplicate if its name (1st arg) was already seen earlier in the file.
"""
import re

content = open('test/engine_test.dart', encoding='utf-8').read()
content = content.replace('\r\n', '\n').replace('\r', '\n')

lines = content.split('\n')
seen_names = set()
delete_ranges = []  # list of (start_idx, end_idx) inclusive

BACKSLASH = chr(92)

i = 0
while i < len(lines):
    line = lines[i]
    m = re.match(r"\s*shqlBoth(?:Stdlib)?\('([^']*)'", line)
    if not m:
        i += 1
        continue

    name = m.group(1)
    start = i

    # Scan to find the closing ); by tracking depth
    depth = 0
    j = i
    in_string = False
    string_char = None
    triple = False
    done = False

    while j < len(lines) and not done:
        row = lines[j]
        ci = 0
        while ci < len(row) and not done:
            c = row[ci]
            if in_string:
                if triple:
                    if row[ci:ci+3] == string_char * 3:
                        in_string = False
                        ci += 2
                else:
                    if c == BACKSLASH:
                        ci += 1  # skip escaped char
                    elif c == string_char:
                        in_string = False
            else:
                if c in '([{':
                    depth += 1
                elif c in ')]}':
                    depth -= 1
                    if depth == 0:
                        if name in seen_names:
                            delete_ranges.append((start, j))
                        else:
                            seen_names.add(name)
                        i = j + 1
                        done = True
                elif row[ci:ci+4] in ('r"""', "r'''"):
                    in_string = True
                    string_char = row[ci+1]
                    triple = True
                    ci += 3
                elif row[ci:ci+3] in ('"""', "'''"):
                    in_string = True
                    string_char = c
                    triple = True
                    ci += 2
                elif c in ('"', "'"):
                    in_string = True
                    string_char = c
                    triple = False
            ci += 1
        if not done:
            j += 1

    if not done:
        i += 1

print(f'Total unique names: {len(seen_names)}')
print(f'Duplicate blocks to delete: {len(delete_ranges)}')
for s, e in delete_ranges:
    print(f'  lines {s+1}-{e+1}: {lines[s].strip()[:70]}')

delete_set = set()
for s, e in delete_ranges:
    for x in range(s, e + 1):
        delete_set.add(x)

new_lines = [line for i, line in enumerate(lines) if i not in delete_set]
print(f'Lines: {len(lines)} -> {len(new_lines)} (removed {len(lines)-len(new_lines)})')

open('test/engine_test.dart', 'w', encoding='utf-8').write('\n'.join(new_lines))
print('Done.')
