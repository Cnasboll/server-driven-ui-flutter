"""Remove shqlBoth/shqlBothStdlib duplicates from engine_test.dart.
Two tests are duplicates if their SHQL source, after collapsing whitespace,
is identical.  The FIRST occurrence is kept; later ones are removed.
"""
import re

BACKSLASH = chr(92)

content = open('test/engine_test.dart', encoding='utf-8').read()
content = content.replace('\r\n', '\n').replace('\r', '\n')
lines = content.split('\n')

def normalize(src):
    """Remove all whitespace — two SHQL programs that differ only in
    spacing compile to identical bytecode and are semantically the same."""
    return re.sub(r'\s+', '', src)

# --- Parse: find all shqlBoth/shqlBothStdlib calls with their char ranges ---

def parse_calls(text):
    """Yield (start_char, end_char, name, src_value) for each call."""
    pos = 0
    while pos < len(text):
        # Find token
        i1 = text.find('shqlBoth(', pos)
        i2 = text.find('shqlBothStdlib(', pos)
        if i1 == -1 and i2 == -1:
            break
        if i1 == -1:
            idx, tok_len = i2, 15
        elif i2 == -1:
            idx, tok_len = i1, 9
        elif i1 <= i2:
            idx, tok_len = i1, 9
        else:
            idx, tok_len = i2, 15

        # Must be at start of line (only whitespace before on same line)
        line_start = text.rfind('\n', 0, idx) + 1
        prefix = text[line_start:idx]
        if prefix.strip():
            pos = idx + tok_len
            continue

        call_start = idx
        pos = idx + tok_len  # past '('

        # Parse first argument (name, a Dart string)
        def skip_ws(p):
            while p < len(text) and text[p] in ' \t\n\r':
                p += 1
            return p

        def parse_str(p):
            raw = False
            if p < len(text) and text[p] == 'r':
                raw = True
                p += 1
            q = text[p]
            p += 1
            triple = text[p:p+2] == q*2
            if triple:
                p += 2
            buf = []
            while p < len(text):
                if triple:
                    if text[p:p+3] == q*3:
                        p += 3
                        break
                else:
                    if text[p] == q:
                        p += 1
                        break
                if not raw and text[p] == BACKSLASH:
                    p += 1
                    if p < len(text):
                        esc = {'n': '\n', 'r': '\r', 't': '\t',
                               BACKSLASH: BACKSLASH, '$': '$'}
                        buf.append(esc.get(text[p], text[p]))
                        p += 1
                else:
                    buf.append(text[p])
                    p += 1
            return ''.join(buf), p

        def parse_str_arg(p):
            p = skip_ws(p)
            buf = []
            while p < len(text) and text[p] in ('"', "'", 'r'):
                s, p = parse_str(p)
                buf.append(s)
                p = skip_ws(p)
            return ''.join(buf), p

        try:
            pos = skip_ws(pos)
            name, pos = parse_str_arg(pos)
            pos = skip_ws(pos)
            if pos >= len(text) or text[pos] != ',':
                continue
            pos += 1
            src, pos = parse_str_arg(pos)
            # Find closing ); by tracking depth from call_start
            depth = 0
            p = call_start + tok_len - 1  # at the '('
            in_str = False
            str_char = None
            is_triple = False
            while p < len(text):
                c = text[p]
                if in_str:
                    if is_triple:
                        if text[p:p+3] == str_char * 3:
                            in_str = False
                            p += 2
                    else:
                        if c == BACKSLASH:
                            p += 1
                        elif c == str_char:
                            in_str = False
                else:
                    if c in '([{':
                        depth += 1
                    elif c in ')]}':
                        depth -= 1
                        if depth == 0:
                            yield (call_start, p, name, src)
                            pos = p + 1
                            break
                    elif text[p:p+4] in ('r"""', "r'''"):
                        in_str = True
                        str_char = text[p+1]
                        is_triple = True
                        p += 3
                    elif text[p:p+3] in ('"""', "'''"):
                        in_str = True
                        str_char = c
                        is_triple = True
                        p += 2
                    elif c in ('"', "'"):
                        in_str = True
                        str_char = c
                        is_triple = False
                p += 1
        except Exception:
            pass

calls = list(parse_calls(content))
print(f'Found {len(calls)} calls')

seen_norm = {}  # norm_src -> (call_idx, name)
to_delete = []  # char ranges to delete

for i, (start, end, name, src) in enumerate(calls):
    norm = normalize(src)
    if norm in seen_norm:
        prev_name = seen_norm[norm][1]
        print(f'  DUPLICATE: "{name}" == "{prev_name}" (normalized src match)')
        to_delete.append((start, end + 1))  # +1 to include closing char
    else:
        seen_norm[norm] = (i, name)

print(f'Removing {len(to_delete)} duplicate calls')

# Build new content by skipping deleted ranges
# Sort by start descending to delete from end
to_delete.sort(key=lambda x: x[0], reverse=True)

chars = list(content)
for start, end in to_delete:
    # Also remove leading whitespace on same line before 'start'
    s = start
    while s > 0 and chars[s-1] in (' ', '\t'):
        s -= 1
    # And the trailing newline after 'end'
    e = end
    if e < len(chars) and chars[e] == '\n':
        e += 1
    del chars[s:e]

new_content = ''.join(chars)
open('test/engine_test.dart', 'w', encoding='utf-8').write(new_content)
print(f'Lines: {content.count(chr(10))} -> {new_content.count(chr(10))}')
print('Done.')
