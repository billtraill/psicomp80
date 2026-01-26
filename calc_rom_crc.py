import zlib, pathlib, hashlib
p = pathlib.Path("psicomp80.rom")
data = p.read_bytes()
crc = zlib.crc32(data) & 0xffffffff
sha1 = hashlib.sha1(data).hexdigest()
print(f"CRC({crc:08x}) SHA1({sha1})")
