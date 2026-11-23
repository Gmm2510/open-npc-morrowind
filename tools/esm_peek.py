"""Reads Morrowind .esm/.esp records (read-only) to check layouts against the real game files."""
import struct, sys

def records(path):
    with open(path, 'rb') as f:
        data = f.read()
    i = 0
    while i < len(data):
        rtype = data[i:i+4].decode('latin1'); size, unk, flags = struct.unpack_from('<III', data, i+4)
        body = data[i+16:i+16+size]
        subs = []; j = 0
        while j < len(body):
            st = body[j:j+4].decode('latin1'); ss = struct.unpack_from('<I', body, j+4)[0]
            subs.append((st, body[j+8:j+8+ss])); j += 8 + ss
        yield rtype, flags, subs
        i += 16 + size

def zs(b):
    return b.split(b'\0')[0].decode('latin1')

if __name__ == '__main__':
    mode, path = sys.argv[1], sys.argv[2]
    if mode == 'header':
        for rtype, flags, subs in records(path):
            print(rtype, 'flags', flags)
            for st, sd in subs:
                if st == 'HEDR':
                    ver, ftype = struct.unpack_from('<fI', sd, 0); n = struct.unpack_from('<I', sd, 296)[0]
                    print('  HEDR len', len(sd), 'version', ver, hex(struct.unpack_from('<I', sd, 0)[0]), 'type', ftype, 'author', zs(sd[8:40]), 'records', n)
                else:
                    print(' ', st, len(sd), zs(sd) if st == 'MAST' else struct.unpack('<Q', sd)[0] if st == 'DATA' else '')
            break
        print('total records after header:', sum(1 for _ in records(path)) - 1)
    elif mode == 'npc':
        want = sys.argv[3].lower()
        for rtype, flags, subs in records(path):
            if rtype != 'NPC_': continue
            d = dict((st, sd) for st, sd in subs)
            if zs(d.get('NAME', b'')).lower() != want: continue
            print('NPC_ record flags', flags)
            for st, sd in subs:
                if st in ('NAME', 'FNAM', 'RNAM', 'CNAM', 'ANAM', 'BNAM', 'KNAM', 'SCRI', 'MODL'):
                    print(' ', st, len(sd), repr(zs(sd)))
                elif st == 'NPCO':
                    print(' ', st, len(sd), struct.unpack_from('<i', sd, 0)[0], repr(zs(sd[4:])))
                else:
                    print(' ', st, len(sd), sd.hex())
            break
    elif mode == 'bodies':
        pat = sys.argv[3].lower()
        for rtype, flags, subs in records(path):
            if rtype == 'BODY':
                d = dict((st, sd) for st, sd in subs); n = zs(d.get('NAME', b''))
                if pat in n.lower(): print(n, zs(d.get('FNAM', b'')), d.get('BYDT', b'').hex())
    elif mode == 'females':
        race = sys.argv[3].lower(); k = 0
        for rtype, flags, subs in records(path):
            if rtype != 'NPC_': continue
            d = dict((st, sd) for st, sd in subs)
            fl = struct.unpack('<I', d['FLAG'])[0] if 'FLAG' in d else 0
            if (fl & 1) and zs(d.get('RNAM', b'')).lower() == race:
                print(zs(d['NAME']), '|', zs(d.get('FNAM', b'')), '| class', zs(d.get('CNAM', b'')), '| flag', hex(fl), '| npdt', len(d.get('NPDT', b'')), '| head', zs(d.get('BNAM', b'')), '| hair', zs(d.get('KNAM', b'')))
                k += 1
                if k >= 12: break
