"""Complete dark-synth audio edition. NumPy synthesis; FFmpeg float PCM -> Vorbis q10.

Run: python3 tools/generate_dark_audio.py --force
Preview: python3 tools/generate_dark_audio.py --only shared/title_theme --dry-run
All existing audio paths are retained. Ownership/provenance uses the project registry.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import pathlib
import re
import subprocess
import time
import tempfile
from functools import lru_cache

import numpy as np
from scipy.signal import butter, sosfilt, resample_poly, fftconvolve
import audio_synth as A
import generate_foley as F
import generate_sfx as S
import generate_weather_audio as W
from generated_manifest import write_generated_bytes_set

ROOT = pathlib.Path(__file__).resolve().parents[1]
AUDIO = ROOT / 'apps/game/client/assets/audio'
SR = 48000
A.SAMPLE_RATE = SR
SEED = 20260928
# MIDI root, tempo, room decay, timbre. Keys stay consistent across adaptive layers.
REALMS = {
    'forgotten_castle': (38, 88, 2.8, 'stone'),
    'crystal_caverns': (40, 92, 3.5, 'glass'),
    'poison_swamp': (36, 76, 1.9, 'rot'),
    'frozen_fortress': (37, 90, 3.1, 'ice'),
    'dark_cathedral': (34, 80, 4.2, 'organ'),
    'iron_vault': (35, 104, 1.8, 'iron'),
    'prism_depths': (41, 96, 3.4, 'glass'),
    'venom_mire': (33, 74, 2.3, 'rot'),
    'glacial_hollow': (36, 84, 3.8, 'ice'),
    'umbral_chapel': (32, 78, 4.5, 'organ'),
    'shared': (38, 72, 3.2, 'stone'),
}
SCALE = [0, 2, 3, 5, 7, 8, 10]

def hz(note):
    return 440 * 2 ** ((note - 69) / 12)

def degree(root, d):
    octv, i = divmod(d, 7)
    return root + SCALE[i] + octv * 12

def rng_for(name):
    return np.random.default_rng(int.from_bytes(hashlib.sha256(f'{SEED}:{name}'.encode()).digest()[:8], 'little'))

def low(x, cutoff):
    return sosfilt(butter(3, cutoff, fs=SR, output='sos'), x, axis=0).astype(np.float32)

@lru_cache(maxsize=256)
def voice(note, seconds, kind='bow'):
    """Band-limited additive oscillators: retro colour without aliasing or crushed masters."""
    t = np.arange(round(seconds * SR), dtype=np.float64) / SR
    f = hz(note)
    vibrato = .0024 * np.sin(2*np.pi*4.7*t) * np.minimum(t/.4, 1)
    phase = 2*np.pi*f * (t + .0013*np.sin(2*np.pi*.37*t)/(2*np.pi*.37))
    phase += 2*np.pi*f*np.cumsum(vibrato)/SR
    x = np.zeros(len(t), dtype=np.float64)
    count = min(20, int(6500/f))
    for h in range(1, count+1):
        if kind == 'pulse':
            weight = np.sin(np.pi*.32*h) / h**1.5
        elif kind == 'choir':
            weight = (0.18 + np.exp(-((f*h-650)/320)**2)) / h**1.4
        elif kind == 'bell':
            weight = 1/h**2
        else:
            weight = 1/h**1.45
        x += weight*np.sin(phase*h + (.07*h*np.sin(2*np.pi*.21*t)))
    if kind == 'bell':
        x *= np.exp(-t*3.0/max(seconds,.1))
    elif kind == 'pulse':
        x *= np.exp(-t*4.0/max(seconds,.1))
    attack = min(.19 if kind in ('bow', 'choir') else .009, seconds*.2)
    release = min(.38, seconds*.3)
    env = np.minimum(t/attack, 1)*np.minimum((seconds-t)/release, 1)
    return (x * env * .55).astype(np.float32)

def place(out, sound, at, gain=1., pan=0., loop=True):
    start = round(at*SR)
    x = np.asarray(sound)
    if x.ndim == 1:
        x = x[:, None]*np.array([np.sqrt((1-pan)/2), np.sqrt((1+pan)/2)])
    if loop:
        start %= len(out)
        count = min(len(x), len(out)-start)
        out[start:start+count] += x[:count]*gain
        if count < len(x):
            out[:len(x)-count] += x[count:]*gain
    else:
        count = min(len(x), len(out)-start)
        if count > 0:
            out[start:start+count] += x[:count]*gain

def room(x, decay, wet, rng, loop):
    """Decorrelated stereo chamber with dry attack and damped late reflections."""
    ir_len = round(decay*SR)
    t = np.arange(ir_len)/SR
    result = x.copy()
    for ch in range(2):
        ir = low(rng.normal(size=ir_len), 1800) * np.exp(-7*t/decay)
        ir[:int(.024*SR)] = 0
        ir /= max(np.linalg.norm(ir), 1e-9)
        ir *= .25
        for delay, gain in [(.031, .33), (.057, .21), (.083, -.14), (.137, .10)]:
            ir[round((delay+ch*.003)*SR)] += gain
        tail = fftconvolve(x[:,ch], ir).astype(np.float32)
        result[:,ch] += wet*tail[:len(x)]
        if loop:
            result[:len(tail)-len(x),ch] += wet*tail[len(x):]
    return result

def music(realm, kind, rng):
    root, bpm, decay, colour = REALMS[realm]
    if kind == 'title_theme': bpm = 68
    if kind == 'hub_theme': bpm, root = 72, 38
    beat = 60/bpm
    bars = 32 if kind in ('boss_theme', 'title_theme') else 24
    seconds = bars*4*beat
    out = np.zeros((round(seconds*SR), 2), np.float32)
    # Eight-bar harmonic sentence: i - VI - III - VII / iv - VI - V - i.
    chords = [(0,3,7), (-4,0,3), (3,7,10), (-2,2,5),
              (5,8,12), (-4,0,3), (-5,-1,2), (0,3,7)]
    realm_index = list(REALMS).index(realm)
    motif = [0, 2, 4, 3, 2, 1, -1, 0]
    if colour == 'ice': motif = [4,3,2,0,-1,2,1,0]
    if colour == 'rot': motif = [0,1,2,1,-1,0,-3,-1]
    if colour == 'glass': motif = [0,4,2,5,4,2,1,0]
    if colour == 'organ': motif = [0,-1,0,2,3,2,-1,0]
    battle = kind in ('combat_loop', 'boss_theme')
    boss = kind == 'boss_theme'
    explore = kind == 'explore_loop'
    drum = A.war_drum(1.15, rng, pitch=55+realm_index*1.7)
    skin = low(A.snare(.34, rng), 2400)
    for bar in range(bars):
        chord = chords[(bar//2) % 8]
        at = bar*4*beat
        section = bar//8
        intensity = [.72, .88, 1., .84][section]
        # Open fifths and inner voices move with harmony, avoiding a static drone.
        if bar % 2 == 0:
            length = 8*beat+.65
            for i, interval in enumerate(chord):
                place(out, voice(root+12+interval, length, 'choir' if colour=='organ' else 'bow'),
                      at, .13*intensity, [-.65,.15,.65][i])
            place(out, voice(root+chord[0], length, 'bow'), at, .20, 0)
        # Cello-range leitmotif. Later phrases answer the first with changed rhythm/register.
        if not explore or bar % 4 in (1,2):
            d = motif[(bar+realm_index%3) % 8]
            melodic_note = degree(root+12, d)
            if section == 2 and bar % 4 == 2: melodic_note += 12
            place(out, voice(melodic_note, beat*(3.2 if explore else 2.8), 'bow'),
                  at+beat*.5, .22 if battle else .33, -.22)
            if bar % 2 == 1:
                place(out, voice(degree(root+12, motif[(bar+1)%8]), beat*1.25, 'bow'),
                      at+2.8*beat, .18, .23)
        # A quiet, filtered pulse supplies the pixel-era identity below the strings.
        if not explore or bar % 4 == 0:
            steps = 8 if battle else 4
            for step in range(steps):
                interval = chord[[0,2,1,2][step%4]]
                place(out, voice(root+12+interval, beat*.72, 'pulse'),
                      at+step*4*beat/steps, (.11 if battle else .065)*intensity,
                      -.4 if step%2 else .4)
        if colour in ('glass','ice') or kind == 'hub_theme':
            if bar%2 == 0:
                place(out, voice(root+24+chord[1], beat*2, 'bell'), at+beat*1.5, .07, .55)
        if battle or (kind=='title_theme' and section in (1,2)):
            hits = [0,1.5,2.5,3.5] if boss else [0,2.5]
            for j, pos in enumerate(hits):
                place(out, drum, at+pos*beat, (.52 if j==0 else .28)*intensity, (j%2-.5)*.35)
            if battle:
                place(out, skin, at+2*beat, .18, .2)
            if bar%8 == 7:
                for j in range(3):
                    place(out, drum, at+(3+j*.25)*beat, .17+j*.07, -.3+j*.3)
        if boss and section != 0:
            for i in [0,2]:
                place(out, voice(root+12+chord[i], 3.5*beat, 'choir'), at, .19, i*.4-.4)
        if kind=='hub_theme' and bar%2==0:
            place(out, voice(root+19, 3*beat, 'bell'), at+.7*beat, .12, -.35)
    return room(out, decay, .40 if battle else .52, rng, True)

def ambience(name, rng):
    realm = name.split('/')[0]
    root, _, decay, colour = REALMS.get(realm, REALMS['shared'])
    if 'portal_hum_' in name:
        suffix = name.rsplit('_', 1)[-1]
        aliases = {'castle':'forgotten_castle', 'crystal':'crystal_caverns', 'swamp':'poison_swamp',
                   'frozen':'frozen_fortress', 'cathedral':'dark_cathedral', 'vault':'iron_vault',
                   'prism':'prism_depths', 'mire':'venom_mire', 'hollow':'glacial_hollow', 'umbral':'umbral_chapel'}
        root, _, decay, colour = REALMS.get(aliases.get(suffix, 'shared'), REALMS['shared'])
    seconds = 32 if realm != 'sfx' else 20
    n = seconds*SR
    t = np.arange(n)/SR
    out = np.zeros((n,2), np.float32)
    rain = 'rain' in name or 'fountain' in name
    fire = 'brazier' in name
    for ch in range(2):
        noise = low(rng.normal(size=n), 2800 if rain else 650)
        noise *= .7+.18*np.sin(2*np.pi*t/seconds*(3+ch))
        out[:,ch] = noise*.15
        # Integer cycle counts make the low drone exactly periodic.
        f = round(hz(root)*.5*seconds)/seconds
        out[:,ch] += .045*np.sin(2*np.pi*f*t + .12*ch)
        out[:,ch] += .018*np.sin(2*np.pi*round(f*1.5*seconds)/seconds*t)
    if 'portal' in name:
        for k in range(8):
            place(out, voice(root+12+(k%3)*7, 3.4, 'choir'), k*2.5, .07, np.sin(k)*.6)
    else:
        for k in range(100 if fire or rain else 12):
            at = float(rng.uniform(0,seconds))
            dur = .09 if fire or rain else 1.2
            sound = A.modal([90,151,267] if colour in ('iron','stone') else [160,241,388], dur, rng=rng)
            place(out, sound, at, float(rng.uniform(.015,.045)), float(rng.uniform(-.8,.8)))
    # Circular spectral filtering removes the white-noise boundary discontinuity.
    spec = np.fft.rfft(out, axis=0)
    freq = np.fft.rfftfreq(n,1/SR)
    spec *= (1/(1+(freq/ (2400 if rain else 1300))**6))[:,None]
    return room(np.fft.irfft(spec,n,axis=0).astype(np.float32), decay, .35, rng, True)

def one_shot(name, rng):
    base = re.sub(r'_0[1-4]$', '', name)
    variant = int(name[-1]) if re.search(r'_0[1-4]$',name) else 0
    builders = {**F.GENERATORS, **F.TAIL_GENERATORS, **S.SIMPLE_GENERATORS, **W.BUILDERS,
                'ui_interact_near': S.ui_interact_near}
    if name in builders or base in builders:
        x = builders.get(name, builders.get(base))(rng)
        # New render, lower tuning, longer body; preserves the recognizable material gestures.
        x = resample_poly(x, 25, 28 if name.startswith('npc') else 22, axis=0)
    elif name.startswith('step_'):
        material = name.split('_')[1]
        fn = {'stone': F.footstep_stone,'wood': F.footstep_wood,
              'snow':F.footstep_snow_variant,'water':F.footstep_water}[material]
        x = fn(rng, variant)
    elif name.startswith('sting_'):
        seqs = {'boss':[0,1,7,-12], 'clear':[0,3,7,12], 'key':[0,7,12],
                'lock':[7,3,0], 'poise_break':[1,0,-12], 'rare_drop':[0,7,10,15],
                'secret':[0,3,10,7], 'shortcut':[0,5,7,12], 'personal_best':[0,3,7,14,12]}
        seq = seqs[name[6:]]
        x = np.zeros((SR*4,2),np.float32)
        for i,d in enumerate(seq):
            place(x, voice(50+d, 2., 'bell'), i*.27, .45, (i%2-.5)*.5, False)
            place(x, voice(38+d, 2.4, 'bow'), i*.27, .17, 0, False)
        if 'boss' in name or 'poise' in name:
            place(x,A.war_drum(1.8,rng,54),0,.6,0,False)
    else:
        seconds = .75
        if base in ('death','execution'): seconds=1.6
        if base.startswith('windup'): seconds=.55
        if base=='ui_click': seconds=.14
        t=np.arange(round(seconds*SR))/SR
        noise=low(rng.normal(size=len(t)), 2600)
        if base.startswith(('swing','dodge','windup')):
            sweep=np.sin(np.pi*np.minimum(t/(seconds*.85),1))**2
            x=noise*sweep*.7
            x+=.20*np.sin(2*np.pi*(90*t+70*t*t))*sweep
            if base.startswith('windup'):
                x+=voice(43+variant,seconds,'pulse')*.35
        elif base.startswith('heal'):
            x=np.zeros(len(t),np.float32)
            for i,f in enumerate([174.6,220,261.6]):
                x+=np.sin(2*np.pi*f*t)*np.exp(-t*(2+i))*np.minimum(t/.015,1)*.15
            x+=noise*.09*np.exp(-t*8)
        elif base in ('death','execution'):
            phase=2*np.pi*np.cumsum(120*np.exp(-t*2)+38)/SR
            x=np.sin(phase)*np.exp(-t*3)*.7+noise*np.exp(-t*9)*.25
        elif base=='ui_click':
            x=(np.sin(2*np.pi*240*t)+.3*np.sin(2*np.pi*480*t))*np.exp(-t*40)*.3
        elif base.startswith(('hit','block','parry')):
            metal = 'armor' in base or base.startswith(('block','parry'))
            fundamental=(210 if base.startswith('parry') else 115 if metal else 68)*(1+variant*.037)
            ratios = [1,2.76,5.4,8.93] if metal else [1,1.63,2.21]
            x=sum(np.sin(2*np.pi*fundamental*r*t)*np.exp(-t*(5+j*6))/(1+j*1.5) for j,r in enumerate(ratios))*.45
            x+=noise*np.exp(-t*42)*.48
            x+=np.sin(2*np.pi*(48*t+1.2*(1-np.exp(-t*25))))*np.exp(-t*17)*.35
        else:
            raise ValueError(f'No instrument design for {name}')
        x*=np.minimum(t/.002,1)*np.minimum((seconds-t)/.025,1)
    if x.ndim==1:
        x=np.column_stack([x,x])
    x=low(x,4200 if base.startswith('parry') else 3100)
    x=np.pad(x,((0,round(SR*.3)),(0,0)))
    x=room(x,.42,.15,rng,False)
    x[-480:]*=np.linspace(1,0,480)[:,None]
    return x

def master(x, loop, music_track):
    if not np.isfinite(x).all(): raise ValueError('Non-finite audio')
    # Circular EQ preserves loop tails; minimum-phase EQ for dry one-shots.
    if loop:
        freq=np.fft.rfftfreq(len(x),1/SR)
        eq=(freq**2/(freq**2+28**2))/(1+(freq/6500)**8)
        x=np.fft.irfft(np.fft.rfft(x,axis=0)*eq[:,None],len(x),axis=0).astype(np.float32)
    else:
        x=sosfilt(butter(2,32,'highpass',fs=SR,output='sos'),x,axis=0).astype(np.float32)
    rms=np.sqrt(np.mean(x*x))
    gain=min((.135 if music_track else .19)/max(rms,1e-8), .84/max(np.max(np.abs(x)),1e-8))
    return (x*gain).astype('<f4')

def encode(x):
    return subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-f','f32le','-ar',str(SR),
        '-ac','2','-i','pipe:0','-map_metadata','-1','-c:a','libvorbis','-q:a','10',
        '-metadata','artist=Aumbrye procedural score','-f','ogg','pipe:1'],
        input=x.tobytes(),capture_output=True,check=True).stdout

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--only',help='asset-relative name without .ogg')
    ap.add_argument('--dry-run',action='store_true')
    ap.add_argument('--force',action='store_true')
    args=ap.parse_args()
    paths=sorted(AUDIO.rglob('*.ogg'))
    recipe = hashlib.sha256(b''.join(p.read_bytes() for p in [pathlib.Path(__file__),
        pathlib.Path(A.__file__), pathlib.Path(F.__file__), pathlib.Path(S.__file__), pathlib.Path(W.__file__)])).hexdigest()[:16]
    cache = pathlib.Path(tempfile.gettempdir()) / ('aumbrye-dark-audio-' + recipe)
    cache.mkdir(exist_ok=True)
    outputs=[]
    report=[]
    start=time.time()
    for path in paths:
        name=path.relative_to(AUDIO).with_suffix('').as_posix()
        if args.only and name != args.only: continue
        cached = cache / (name.replace('/', '__') + '.ogg')
        metadata = cached.with_suffix('.json')
        if cached.exists() and metadata.exists():
            encoded = cached.read_bytes()
            row = json.loads(metadata.read_text())
            if hashlib.sha256(encoded).hexdigest() != row['after_sha256']:
                raise ValueError(f'Corrupt candidate cache: {cached}')
            row['before_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
            outputs.append((path, encoded))
            report.append(row)
            print(f'{len(outputs):3} {name:48} cached', flush=True)
            continue
        realm,kind=name.split('/')
        loop='loop=true' in pathlib.Path(str(path)+'.import').read_text()
        music_track=realm!='sfx' and not kind.startswith('sting_') and kind!='ambience_loop'
        rng=rng_for(name)
        if music_track: x=music(realm,kind,rng)
        elif loop: x=ambience(name,rng)
        else: x=one_shot(kind,rng)
        x=master(x,loop,music_track)
        encoded=encode(x)
        outputs.append((path,encoded))
        report.append({'path':str(path.relative_to(ROOT)), 'seconds':round(len(x)/SR,4),
            'loop':loop,'sample_rate':SR,'channels':2,'peak_db':round(20*np.log10(np.max(np.abs(x))),2),
            'rms_db':round(20*np.log10(np.sqrt(np.mean(x*x))),2),
            'before_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
            'after_sha256':hashlib.sha256(encoded).hexdigest()})
        print(f'{len(outputs):3} {name:48} {len(x)/SR:6.1f}s {len(encoded)//1024:5} KiB',flush=True)
        cached.write_bytes(encoded)
        metadata.write_text(json.dumps(report[-1]))
        voice.cache_clear()
    if not outputs: raise ValueError('No matching audio assets')
    sources=[pathlib.Path(__file__).with_name(n) for n in ['audio_synth.py','generate_foley.py','generate_sfx.py','generate_weather_audio.py','generated_manifest.py']]
    write_generated_bytes_set(outputs,generator=pathlib.Path(__file__).resolve(),sources=sources,
                              force=args.force,dry_run=args.dry_run,seed=SEED)
    target=ROOT/'tools/dark-audio-render-report.json'
    if not args.dry_run and not args.only: target.write_text(json.dumps(report,indent=2)+'\n')
    print(f'{"Validated" if args.dry_run else "Published"} {len(outputs)} assets in {time.time()-start:.1f}s',flush=True)

if __name__=='__main__': main()
