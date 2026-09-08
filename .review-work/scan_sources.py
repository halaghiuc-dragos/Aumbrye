from pathlib import Path
import ast, collections, csv, hashlib, json, re, struct
root=Path('.')
skip_dirs={'.git','.godot','node_modules','bin','obj','.venv','__pycache__','.pytest_cache','.ruff_cache','.claude','.review-work','artifacts','docs','reports'}
text_ext={'.gd','.cs','.gdshader','.gdshaderinc','.tscn','.tres','.json','.py','.mjs','.tsx','.ts','.js','.css','.cfg','.godot','.yaml','.yml','.toml','.xml','.props','.csproj','.sh','.ps1','.html','.csv','.svg','.import','.uid','.conf','.example','.txt','.sln'}
rows=[]; issues=[]; hashes=collections.defaultdict(list); text_cache={}; parsed={}; total_bytes=0
for p in sorted(root.rglob('*')):
 if not p.is_file() or any(x in skip_dirs for x in p.parts):continue
 s=p.as_posix()
 if s=='GAME_IMPROVEMENT_PLAN.md' or s.startswith('GAME_REVIEW_FILE_COVERAGE'):continue
 if p.suffix=='.md':rows.append([s,'excluded: existing document',0,0,'']);continue
 if '/scripts/tools/' in s and any(x in p.stem for x in ['audit','probe','capture','sweep','report','health','walk','watcher']):
  rows.append([s,'excluded: existing audit/probe',0,0,'']);continue
 if ('/debug/' in s and any(x in p.stem for x in ['audit','capture','probe','sweep'])) or ('audit' in p.stem and s.startswith('scripts/')):
  rows.append([s,'excluded: existing audit/probe',0,0,'']);continue
 if '/addons/' in s:rows.append([s,'excluded: third-party editor addon',p.stat().st_size,0,'']);continue
 if p.name in {'.env','.mcp.json'}:rows.append([s,'excluded: potentially private configuration',p.stat().st_size,0,'']);continue
 raw=p.read_bytes();total_bytes+=len(raw);digest=hashlib.sha256(raw).hexdigest();hashes[digest].append(s)
 status='binary bytes/header/hash checked; not visually or aurally reviewed';lines=0
 if p.suffix in text_ext or p.name in {'Dockerfile','LICENSE'}:
  try:t=raw.decode('utf-8-sig');lines=len(t.splitlines());text_cache[s]=t;status='full-file automated text/structure scan; focused manual review by system'
  except UnicodeDecodeError:t=None
  if t is not None:
   if p.suffix=='.json':
    try:parsed[s]=json.loads(t)
    except Exception as e:issues.append({'file':s,'type':'json_parse','detail':str(e)})
   if p.suffix=='.py':
    try:ast.parse(t)
    except Exception as e:issues.append({'file':s,'type':'python_parse','detail':str(e)})
   if p.suffix in {'.gd','.tscn','.tres','.json','.godot','.cfg'}:
    for m in re.finditer(r'(?P<q>["\'])(res://[^"\'\n]+)(?P=q)',t):
     ref=m.group(2)
     if any(x in ref for x in ['%','{','*']):continue
     target=Path('apps/game/client')/ref[6:]
     if not target.exists():issues.append({'file':s,'line':t.count('\n',0,m.start())+1,'type':'missing_literal_resource_candidate','detail':ref})
   if p.suffix=='.gd':
    funcs=list(re.finditer(r'^(?:static )?func ([\w]+)\([^\n]*',t,re.M))
    for i,m in enumerate(funcs):
     body=t[m.start():funcs[i+1].start() if i+1<len(funcs) else len(t)]
     real=[l.strip() for l in body.splitlines()[1:] if l.strip() and not l.lstrip().startswith('#')]
     if real==['pass']:issues.append({'file':s,'line':t.count('\n',0,m.start())+1,'type':'empty_method','detail':m.group(1)})
 if p.suffix=='.png' and raw[:8]==b'\x89PNG\r\n\x1a\n':status+=f'; PNG {struct.unpack(">II",raw[16:24])}'
 if p.suffix=='.ogg' and raw[:4]!=b'OggS':issues.append({'file':s,'type':'bad_ogg_header'})
 if p.suffix=='.vox' and raw[:4]!=b'VOX ':issues.append({'file':s,'type':'bad_vox_header'})
 rows.append([s,status,len(raw),lines,digest])
with Path('GAME_REVIEW_FILE_COVERAGE.csv').open('w',newline='') as f:
 w=csv.writer(f);w.writerow(['file','inspection','bytes','lines','sha256']);w.writerows(rows)
Path('.review-work/scan_findings.json').write_text(json.dumps(issues,indent=2))
# Data behavior shapes for all gameplay content.
metrics={}
for group in ['enemies','bosses','weapons','rooms','biomes','relics','quests','items/equipment','traps']:
 ds={p:d for p,d in parsed.items() if p.startswith('content/'+group+'/') and isinstance(d,dict)}
 metrics[group]={'files':len(ds),'keys':dict(collections.Counter(k for d in ds.values() for k in d).most_common(14))}
Path('.review-work/content_metrics.json').write_text(json.dumps(metrics,indent=2))
summary={'inventory_entries':len(rows),'scanned_text_files':len(text_cache),'parsed_json_files':len(parsed),'bytes_read':total_bytes,'issue_types':dict(collections.Counter(x['type'] for x in issues)),'duplicate_groups':len([v for v in hashes.values() if len(v)>1]),'largest_gd':sorted([(len(t.splitlines()),p) for p,t in text_cache.items() if p.endswith('.gd')],reverse=True)[:12]}
Path('.review-work/scan_summary.json').write_text(json.dumps(summary,indent=2));print(json.dumps(summary,indent=2))
for issue in issues[:35]:print(json.dumps(issue))
