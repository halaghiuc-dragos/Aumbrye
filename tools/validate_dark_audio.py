"""Decode every replacement with FFmpeg and check coverage, headroom and loop seams."""
import hashlib
import json
from pathlib import Path
import subprocess
import numpy as np

ROOT=Path(__file__).resolve().parents[1]

def main():
    report=json.loads((ROOT/'tools/dark-audio-render-report.json').read_text())
    expected={str(p.relative_to(ROOT)) for p in (ROOT/'apps/game/client/assets/audio').rglob('*.ogg')}
    assert expected=={r['path'] for r in report}, 'Incomplete audio coverage'
    results=[]
    hashes=set()
    for r in report:
        path=ROOT/r['path']
        digest=hashlib.sha256(path.read_bytes()).hexdigest()
        assert digest==r['after_sha256'] and digest!=r['before_sha256'], f'Not replaced: {path}'
        assert digest not in hashes, f'Duplicate audio: {path}'
        hashes.add(digest)
        probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-of','json',str(path)]))['streams'][0]
        assert probe['codec_name']=='vorbis' and probe['sample_rate']=='48000' and probe['channels']==2, path
        pcm=subprocess.check_output(['ffmpeg','-v','error','-i',str(path),'-f','f32le','-acodec','pcm_f32le','pipe:1'])
        x=np.frombuffer(pcm,dtype='<f4').reshape(-1,2)
        assert np.isfinite(x).all() and len(x)>0, path
        peak=float(np.max(np.abs(x)))
        rms=float(np.sqrt(np.mean(x*x)))
        assert peak<.99 and rms>.0001, f'Clipped or silent: {path} {peak} {rms}'
        assert abs(len(x)/48000-r['seconds'])<.04, path
        seam=float(np.max(np.abs(x[0]-x[-1])))
        # Codec edges must not create a jump larger than an ordinary short transient.
        if r['loop']:
            assert seam<.05, f'Loop edge discontinuity: {path}: {seam}'
        results.append({'path':r['path'],'decoded_peak_db':round(20*np.log10(peak),2),
                        'decoded_rms_db':round(20*np.log10(rms),2),
                        'loop_edge_delta':round(seam,6) if r['loop'] else None})
    (ROOT/'tools/dark-audio-validation.json').write_text(json.dumps(results,indent=2)+'\n')
    print(f'PASS: {len(results)} replaced, unique, decodable stereo 48 kHz Vorbis files; no clipping, silence, duration or loop-edge failures.')

if __name__=='__main__': main()
