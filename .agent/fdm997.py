from pathlib import Path
import subprocess, tarfile, re
root=Path('.fdm997-evidence')
files=set()
for folder in ('/usr/lib/x86_64-linux-gnu/qt6/qml','/usr/lib/x86_64-linux-gnu/qt6/plugins','/usr/lib/qt6/bin'):
 for p in Path(folder).rglob('*'):
  if p.is_file(): files.add(str(p))
files.update(str(p) for p in Path('/usr/lib/x86_64-linux-gnu').glob('libQt6*.so*') if p.is_file())
queue=list(files)
seen=set()
while queue:
 name=queue.pop()
 if name in seen: continue
 seen.add(name)
 try:
  if Path(name).read_bytes()[:4] != b'\x7fELF': continue
 except OSError: continue
 out=subprocess.run(['ldd',name],capture_output=True,text=True).stdout
 for dep in re.findall(r'=> (/[^\s]+)',out):
  if dep not in files and not any(x in dep for x in ('libc.so','libm.so','libpthread.so','libdl.so','librt.so','libstdc++','libgcc_s')):
   files.add(dep);queue.append(dep)
with tarfile.open(root/'qt-runtime.tar.gz','w:gz',dereference=True) as tar:
 for name in sorted(files): tar.add(name,arcname=name.lstrip('/'),recursive=False)
print('Qt runtime files',len(files),'bytes',(root/'qt-runtime.tar.gz').stat().st_size)
