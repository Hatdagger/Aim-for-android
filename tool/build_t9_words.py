#!/usr/bin/env python3
"""Builds assets/t9_words.txt from the SCOWL-based Hunspell en_US dictionary.
Common words and chat slang go first (that order is the default T9 ranking);
the rest follow, shorter words first. Usage:
  python3 tool/build_t9_words.py /usr/share/hunspell/en_US.dic /usr/share/hunspell/en_US.aff
"""
import re, sys, os

CORE = """i you the to a and it is that of in me my so for have be not do what on this are was
just with your but like all can no yes ok okay hey hi hello lol brb omg ttyl gtg bbl afk idk lmao rofl np thx ty
u ur r k kk wb nm nmu wbu wyd sup yo heh hehe haha ha hah bye cya later night gn gm
im dont cant wont didnt doesnt isnt wasnt thats whats youre ill ive id
get got go going went come came know think want need see look make take say said tell told
good great cool nice fun bad sorry thanks thank please love miss
how why when where who which there here then now today tomorrow tonight yesterday soon
one two three time day week year home work school game games play playing online
about out up down off over back just still really very too much more some any
we they he she them us our their his her him its been were will would could should
from at by an or if as because than also only even well right yeah yea yep nope
new old first last next long little big same different other another
people friend friends guy guys girl man dude mom dad
call text message msg phone chat talk talking
gonna wanna gotta kinda sorta ya yeah
""".split()

def parse_aff(path):
    rules = {}
    lines = open(path, encoding='latin1').read().splitlines()
    i = 0
    while i < len(lines):
        p = lines[i].split()
        if len(p) >= 4 and p[0] == 'SFX' and p[2] in ('Y', 'N'):
            flag, n = p[1], int(p[3])
            lst = []
            for j in range(1, n + 1):
                q = lines[i + j].split()
                strip = '' if q[2] == '0' else q[2]
                add = '' if q[3] == '0' else q[3].split('/')[0]
                cond = q[4] if len(q) > 4 else '.'
                lst.append((strip, add, re.compile(cond + '$')))
            rules[flag] = lst
            i += n
        i += 1
    return rules

def main(dic, aff):
    rules = parse_aff(aff)
    words = []
    seen = set()
    def add(w):
        if w not in seen and re.fullmatch(r"[a-z]+", w):
            seen.add(w); words.append(w)
    for w in CORE:
        add(w)
    rest = []
    for line in open(dic, encoding='latin1').read().splitlines()[1:]:
        word, _, flags = line.partition('/')
        if not re.fullmatch(r"[a-z]+", word):
            continue
        forms = [word]
        for f in flags:
            if f in ('S', 'D', 'G', 'R', 'Y'):
                for strip, addx, cond in rules.get(f, []):
                    if cond.search(word) and (not strip or word.endswith(strip)):
                        forms.append(word[: len(word) - len(strip)] + addx)
        rest.extend(forms)
    rest = sorted(set(rest) - seen, key=lambda w: (len(w), w))
    for w in rest:
        add(w)
    out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'assets', 't9_words.txt')
    open(out, 'w').write('\n'.join(words) + '\n')
    print(len(words), 'words ->', out)

main(sys.argv[1], sys.argv[2])
