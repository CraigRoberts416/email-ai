#!/usr/bin/env python3
"""Capture the actual Rive state machine into a portable review with both endings."""
import base64, concurrent.futures, json, subprocess
from pathlib import Path

P=Path(__file__).resolve().parent
OUT=P/'build'/'mailroom-preview'
OUT.mkdir(parents=True,exist_ok=True)
RIVE=str(Path.home()/'.rive/bin/rive')
sequences={
    'working': (1,[0,5,10,15,20,25,40,50,55,60,65,70,90,140,175]),
    'arrivals':(2,[0,5,10,15,20,25,30,35,40,45,50,55,65]),
    'empty':(4,[0,10,15,20,25,30,35,40,45,50,55,60,65,75]),
}

def capture(job):
    name,phase,frame=job
    path=OUT/f'{name}-{frame}.png'
    subprocess.run([RIVE,str(P),'--artboard=Mailroom',f'--data=phase={phase}',
        f'--advance={frame}','--viewport=576x392','--fit=contain',f'--screenshot={path}'],
        check=True,capture_output=True)
    return str(path)

jobs=[(name,phase,frame) for name,(phase,frames) in sequences.items() for frame in frames]
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    for result in pool.map(capture,jobs): print(result,flush=True)
for name,(phase,frames) in sequences.items():
    lines=[]
    for i,frame in enumerate(frames):
        lines += [f"file '{OUT/name}-{frame}.png'", f'duration {(frames[i+1]-frame)/60 if i+1<len(frames) else (0.083 if name=="working" else 1.5)}']
    lines.append(f"file '{OUT/name}-{frames[-1]}.png'")
    manifest=OUT/f'{name}.txt';manifest.write_text('\n'.join(lines)+'\n')
    subprocess.run(['ffmpeg','-y','-v','error','-f','concat','-safe','0','-i',str(manifest),
        '-vf','split[a][b];[a]palettegen[p];[b][p]paletteuse=dither=none',
        '-loop','0',str(OUT/f'{name}.gif')],check=True)

images={name:'data:image/gif;base64,'+base64.b64encode((OUT/f'{name}.gif').read_bytes()).decode() for name in sequences}
html='''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Little mail robot — animation preview</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#f4f3ef;color:#263542;font:15px system-ui,sans-serif;min-height:100vh;display:grid;place-items:center;padding:24px}
main{max-width:660px;width:100%}small{font-size:11px;letter-spacing:.14em;text-transform:uppercase;color:#697573}h1{font-size:30px;letter-spacing:-.045em;margin:10px 0}p{line-height:1.5;color:#5e6869;margin:0 0 22px}
.scene{position:relative;background:#fff;border:6px solid #13132d;border-radius:38px;overflow:hidden;max-width:430px;margin:auto;box-shadow:0 12px 40px #26354209}
.stage{position:relative}.island{position:absolute;top:10px;left:50%;transform:translateX(-50%);width:94px;height:24px;border-radius:20px;background:#13132d;z-index:2}
#status{position:absolute;bottom:10px;width:100%;text-align:center;font:10px ui-monospace,monospace;letter-spacing:.06em;color:#687274}img{display:block;width:100%;height:auto;image-rendering:pixelated}
.feed{border-top:1px solid #e3e5e8;padding:20px 30px;color:#9aa5a5;font-size:12px}.line{height:7px;background:#eee;margin-top:12px;border-radius:3px;width:82%}.line:last-child{width:57%}
nav{display:flex;gap:8px;flex-wrap:wrap;margin:20px 0 10px}button{border:1px solid #c9ceca;border-radius:100px;padding:12px 18px;background:transparent;color:inherit;font:inherit;cursor:pointer}button[aria-pressed=true]{background:#263542;border-color:#263542;color:#fff}button:focus-visible{outline:3px solid #dea642;outline-offset:3px}.note{font-size:12px}
</style><main><small>Decision Inbox · artwork preview</small><h1>A little nudge to the cloud.</h1>
<p>Your robot knocks on the top of the phone. Mail drops in only when there is something new.</p>
<div class="scene"><div class="island"></div><div class="stage"><img id="art" alt="Round-helmet pixel robot knocking a stick against the phone edge"><div id="status" aria-live="polite">CHECKING YOUR MAILBOX…</div></div><div class="feed">YOUR FEED<div class="line"></div><div class="line"></div></div></div>
<nav aria-label="Refresh outcome"><button data-state="working" aria-pressed="true">Keep knocking</button><button data-state="arrivals" aria-pressed="false">New mail</button><button data-state="empty" aria-pressed="false">No new mail</button></nav>
<p class="note">Actual Rive frames. Endings repeat here for review; the app plays an ending once. This preview is not a TestFlight release.</p></main>
<script>const images=IMAGES;const art=document.querySelector('#art');const status=document.querySelector('#status');art.src=images.working;
document.querySelectorAll('button').forEach(button=>button.onclick=()=>{const state=button.dataset.state;art.src=images[state];status.textContent={working:'CHECKING YOUR MAILBOX…',arrivals:'NEW MAIL ARRIVED',empty:'NO NEW MAIL'}[state];document.querySelectorAll('button').forEach(b=>b.setAttribute('aria-pressed',b===button));});</script></html>'''.replace('IMAGES',json.dumps(images))
(OUT/'index.html').write_text(html)
print(OUT/'index.html')
