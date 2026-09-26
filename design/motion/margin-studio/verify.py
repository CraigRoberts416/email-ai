#!/usr/bin/env python3
"""Compile production vectors; prove gesture poses, loops, quiet poses and endings."""
import hashlib, json, os, struct, subprocess, zlib
from pathlib import Path
P=Path(__file__).resolve().parent
RIVE=os.environ.get('RIVE_BIN',str(Path.home()/'.rive/bin/rive'))

def run(*args):
    return subprocess.run([RIVE,*map(str,args)],check=True,capture_output=True,text=True).stdout

def signature(path):
    data=path.read_bytes(); offset=8; payload=b''; header=b''
    while offset<len(data):
        n=struct.unpack('>I',data[offset:offset+4])[0]; tag=data[offset+4:offset+8]
        if tag==b'IHDR':header=data[offset+8:offset+8+n]
        if tag==b'IDAT':payload+=data[offset+8:offset+8+n]
        offset+=n+12
    return hashlib.sha256(header+zlib.decompress(payload)).hexdigest()

def capture(art,phase,frames,pull=100,active=True):
    name=f'{art}-{phase}-{frames}-{pull}-{active}'
    png=P/'build'/f'{name}.png'; dump=png.with_suffix('.json')
    run(P,f'--artboard={art}',f'--data=phase={phase}',f'--data=pull={pull}',f'--data=active={str(active).lower()}',f'--advance={frames}',f'--screenshot={png}',f'--data-dump={dump}')
    props={p['path']:p['value'] for p in json.loads(dump.read_text())['viewModel']['properties']}
    assert props['phase']==phase and props['pull']==pull and props['active']==active,props
    return signature(png)

verify=json.loads(run(P,'--verify','--format=json'))
assert verify['success'] and not verify['warnings'] and not verify['errors']
inspection=json.loads(run('inspect',P,'--summary'))
assert not inspection['problems'],inspection['problems']
assert [a['name'] for a in inspection['artboards']]==['Receipt','Reading','Closing','Mailroom']
for a in inspection['artboards']:
    assert a['types']['StateMachine']==1
    assert not any('Script' in t for t in a['types'])
results={}
results['gesture_continuity']=len({capture('Receipt',0,30,p) for p in [0,25,60,100]})==4
for art in ['Receipt','Reading']:
    results[art+'_working_moves']=capture(art,1,30)!=capture(art,1,70)
    results[art+'_quiet_still']=capture(art,1,30,active=False)==capture(art,1,100,active=False)
    results[art+'_outcomes_distinct']=len({capture(art,p,100) for p in [0,2,3]})==3
results['saved_empty_distinct']=capture('Reading',4,100)!=capture('Reading',2,100)
results['closing_moves']=capture('Closing',1,2)!=capture('Closing',1,24)
results['closing_finishes']=capture('Closing',1,100)==capture('Closing',1,200)
results['reentry_matches_settled']=capture('Closing',2,100)==capture('Closing',1,100)
results['mailroom_pull_poses']=len({capture('Mailroom',0,30,p) for p in [0,50,100]})==3
results['mailroom_knocks']=capture('Mailroom',1,30)!=capture('Mailroom',1,64)
results['mailroom_quiet_still']=capture('Mailroom',1,30,active=False)==capture('Mailroom',1,100,active=False)
results['mailroom_arrivals_fall']=capture('Mailroom',2,15)!=capture('Mailroom',2,40)
results['mailroom_no_mail_settles']=capture('Mailroom',4,80)==capture('Mailroom',4,160)
results['mailroom_endings_distinct']=capture('Mailroom',2,80)!=capture('Mailroom',4,80)
# At every timeline frame, no-arrival/working/recovery must keep all envelopes
# hidden. This is structural as well as visual: a correct caption is not enough.
import xml.etree.ElementTree as E
root=E.parse(P/'scene.rml').getroot()
mailroom=next(a for a in root.findall('Artboard') if a.get('name')=='Mailroom')
letter_ids={n.get('id') for n in mailroom.findall('Node') if n.get('name','').startswith('Falling envelope')}
assert len(letter_ids)==4
for animation in mailroom.findall('LinearAnimation'):
    if animation.get('name')=='Mail breaks loose': continue
    for obj in animation.findall('KeyedObject'):
        if obj.get('objectId') in letter_ids:
            opacity=next(p for p in obj.findall('KeyedProperty') if p.get('propertyKey')=='18')
            assert all(k.get('value')=='0' for k in opacity),animation.get('name')
results['mailroom_letters_require_arrivals']=True
assert all(results.values()),results
build=json.loads(run(P,'--once','--format=json'));assert build['success']
bench_run=subprocess.run([RIVE,str(P),'--artboard=Reading','--data=phase=1','--bench=240'],check=True,capture_output=True,text=True)
bench=bench_run.stdout+bench_run.stderr
report={'checks':results,'bytes':build['data']['bytes'],'benchmark':bench}
(P/'build'/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
