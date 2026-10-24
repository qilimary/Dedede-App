# -*- coding: utf-8 -*-
"""HCAM 文本预处理 V22：完整分片校验，本地有界读取，11小时可续跑。
使用：Kaggle新CPU Notebook，Internet On，将本文件完整粘贴运行，或 %run 本文件。
保存：Save Version → Save & Run All，保留Output。下一次Add Input挂载上次Output。
每10分钟本地检查点；断网/到时正常保存。不需要Kaggle Dataset API、Token或私有上传。
本地检查点只有成功保存Notebook Output后才跨会话保留；强制终止仍可能损失未保存输出。
目标：3.5B主语料+0.1B长尾，24K SentencePiece BPE（非纯字符），兼容V21训练资产格式。
中英文抽样、数字独立、256字节兜底；词表不可与旧模型权重混用，训练时使用随资产生成的tokenizer.model。
11小时是每次会话预算，不保证36亿token一次完成；计数/未完成来源在text_asset_manifest.json。
来源和固定commit记录于清单。仅使用训练分片；来源许可证继续适用。
可选配置：环境变量HCAM_TEXT_CONFIG_JSON指向JSON；通常无需修改配置。
"""
from __future__ import annotations
import argparse, base64, contextlib, dataclasses, hashlib, html, io, json, math, os
import pickle, random, re, selectors, shutil, signal, sqlite3, struct, subprocess, sys
import tarfile, tempfile, time, unicodedata, uuid, threading
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, asdict
from pathlib import Path
from urllib.parse import quote, urlparse
os.environ.setdefault('TOKENIZERS_PARALLELISM', 'false')
os.environ.setdefault('OPENBLAS_NUM_THREADS', '1')
IS_KAGGLE = Path('/kaggle/working').is_dir()
STOP = False
STARTED = time.monotonic()
ACTIVE = None
class Pause(Exception): pass
class SourceUnavailable(Exception): pass
class BadShard(Exception): pass

def dependencies(image=False):
    import importlib.util
    required = {'requests':'requests>=2.31','pyarrow':'pyarrow>=17','numpy':'numpy'}
    required.update({'PIL':'Pillow>=10'} if image else {'sentencepiece':'sentencepiece>=0.2'})
    missing = [p for m,p in required.items() if importlib.util.find_spec(m) is None]
    if missing:
        print('[准备依赖] 首次运行安装缺少的包：'+', '.join(missing), flush=True)
        subprocess.run([sys.executable,'-m','pip','install','-q',*missing], check=True, timeout=240)

def atomic_json(path, data):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    tmp=path.with_name(path.name+'.tmp')
    with open(tmp,'w',encoding='utf-8') as f:
        json.dump(data,f,ensure_ascii=False,indent=2,allow_nan=False);f.flush();os.fsync(f.fileno())
    os.replace(tmp,path)

def sha_file(path):
    h=hashlib.sha256()
    with open(path,'rb') as f:
        for b in iter(lambda:f.read(4<<20),b''):h.update(b)
    return h.hexdigest()

def safe_path(root, name):
    root=Path(root).resolve();p=(root/str(name)).resolve()
    if not p.is_relative_to(root):raise ValueError('资产路径越界：'+str(name))
    return p

def configure(cfg, env):
    if os.environ.get(env):
        d=json.loads(Path(os.environ[env]).read_text(encoding='utf-8'))
        unknown=set(d)-{f.name for f in dataclasses.fields(cfg)}
        if unknown:raise ValueError('未知配置：'+str(unknown))
        for k,v in d.items():setattr(cfg,k,tuple(v) if isinstance(getattr(cfg,k),tuple) else v)
    if not 0 < cfg.session_hours <= 11:raise ValueError('session_hours 必须大于0且不超过11')
    return cfg

def fingerprint(cfg):
    runtime={'session_hours','workers','checkpoint_seconds','local_commit_docs','max_output_gib',
             'max_shard_gib','download_seconds','cache_gib','input_roots','legacy_roots','local_jsonl','local_novels','local_user'}
    return hashlib.sha256(json.dumps({k:v for k,v in asdict(cfg).items() if k not in runtime},sort_keys=True).encode()).hexdigest()

def redact(error):
    s=str(error)
    for k in ('HF_TOKEN','HUGGING_FACE_HUB_TOKEN','KAGGLE_API_TOKEN','KAGGLE_KEY'):
        if os.environ.get(k):s=s.replace(os.environ[k],'[hidden]')
    return re.sub(r'https?://[^\s]+', '[URL]', s)[:350]

def stop_handler(*_):
    global STOP
    STOP=True

class Panel:
    def __init__(self,root):self.root=root;self.last=0
    def update(self,phase,done,total,detail='',force=False):
        now=time.monotonic()
        if not force and now-self.last<20:return
        self.last=now
        atomic_json(self.root/'progress.json',dict(phase=phase,done=done,total=total,detail=detail,time=time.time()))
        print(f'[{phase}] {done:,}/{total:,} ({100*done/max(1,total):.2f}%) {detail}',flush=True)

class Session:
    """数据 fsync → SQLite 提交；恢复时截断未提交尾部。无私有上传 API。"""
    def __init__(self,root,cfg,marker):
        global ACTIVE
        self.root=Path(root).resolve();self.root.mkdir(parents=True,exist_ok=True)
        self.cfg=cfg;self.marker=marker;self.fingerprint=fingerprint(cfg)
        self.started=STARTED;self.last_checkpoint=time.monotonic();self.last_check=0
        self.roots=[Path(x) for x in cfg.input_roots]
        self.roots += [Path('/kaggle/input')] if IS_KAGGLE else []
        self.panel=Panel(self.root);self.cache=self.root/'download_cache';self.cache.mkdir(exist_ok=True)
        self.restore()
        self.db=sqlite3.connect(self.root/'state.sqlite')
        self.db.execute('PRAGMA journal_mode=WAL');self.db.execute('PRAGMA synchronous=FULL')
        self.db.execute('PRAGMA cache_size=-32768')
        self.db.execute('CREATE TABLE IF NOT EXISTS kv(k TEXT PRIMARY KEY,v TEXT NOT NULL)')
        self.db.execute('CREATE TABLE IF NOT EXISTS assets(path TEXT PRIMARY KEY,info TEXT NOT NULL)')
        if self.get('fingerprint',self.fingerprint)!=self.fingerprint:raise ValueError('配置已改变，请使用新工作目录')
        self.put('fingerprint',self.fingerprint);self.put('pipeline',marker)
        self.put('run_id',self.get('run_id',uuid.uuid4().hex))
        self.db.commit();self.recover_files();self.part_bytes=0
        self.initial_generation=self.get('generation',0)
        for desc in self.descriptors():
            if (self.root/desc['path']).is_file():self.part_bytes+=desc['bytes']
        self.old_handlers={}
        if threading.current_thread() is threading.main_thread():
            for sig in (signal.SIGINT,signal.SIGTERM):
                self.old_handlers[sig]=signal.getsignal(sig);signal.signal(sig,stop_handler)
        ACTIVE=self
    def get(self,k,default=None):
        row=self.db.execute('SELECT v FROM kv WHERE k=?',(k,)).fetchone()
        return json.loads(row[0]) if row else default
    def put(self,k,v):self.db.execute('INSERT OR REPLACE INTO kv VALUES (?,?)',(k,json.dumps(v,ensure_ascii=False)))
    def log(self,s):
        print(s,flush=True)
        with open(self.root/'preprocess.log','a',encoding='utf-8') as f:f.write(s+'\n')
    def restore(self):
        if (self.root/'state.sqlite').exists():return
        matches=[]
        for root in self.roots:
            for p in root.rglob('local_run.json') if root.exists() else ():
                try:
                    d=json.loads(p.read_text())
                    if d.get('pipeline')==self.marker and d.get('fingerprint')==self.fingerprint and (p.parent/'state.sqlite').is_file():matches.append((int(d['generation']),p,d))
                except (OSError,ValueError,KeyError):continue
        if not matches:return
        if len({d.get('run_id') for _,_,d in matches})>1:raise ValueError('挂载了不同任务的断点，请只保留同一个任务的各次输出')
        _,p,d=max(matches,key=lambda x:x[0]);self.log('[恢复] '+str(p.parent))
        # 图片已封口分片保留在输入中，不反复复制整个百万图片库。
        for rel in ('state.sqlite','tokenizer_sample.txt','tokenizer','tokenizer.model'):
            src=p.parent/rel;dst=self.root/rel
            if src.is_dir():shutil.copytree(src,dst,dirs_exist_ok=True)
            elif src.is_file():shutil.copyfile(src,dst)
        db=sqlite3.connect(self.root/'state.sqlite')
        if self.marker.startswith('HCAM_TEXT'):
            for raw, in db.execute('SELECT info FROM assets'):
                desc=json.loads(raw);src=p.parent/desc['path'];dst=self.root/desc['path']
                if not src.is_file():raise FileNotFoundError('上次文本输出缺少分片：'+str(src))
                dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst)
        for k,v in db.execute("SELECT k,v FROM kv WHERE k LIKE 'writer:%'"):
            state=json.loads(v)
            if state:
                src=p.parent/state['partial'];dst=self.root/state['partial'];dst.parent.mkdir(parents=True,exist_ok=True)
                if not src.is_file():raise FileNotFoundError('断点未封口分片缺失：'+str(src))
                shutil.copyfile(src,dst)
        db.close()
    def descriptors(self):return [json.loads(x[0]) for x in self.db.execute('SELECT info FROM assets ORDER BY path')]
    def recover_files(self):
        known={x['path'] for x in self.descriptors()}
        states=[json.loads(v) for k,v in self.db.execute("SELECT k,v FROM kv WHERE k LIKE 'writer:%'")]
        partials={s['partial']:s for s in states if s}
        for sub in ('text','images'):
            for p in (self.root/sub).glob('*'):
                rel=str(p.relative_to(self.root))
                if p.is_file() and rel not in known and rel not in partials:p.unlink()
        for rel,s in partials.items():
            p=self.root/rel;n=s.get('bytes',s.get('tokens',0)*2)
            if not p.is_file() or p.stat().st_size<n:raise IOError('断点数据缺失/被截短：'+str(p))
            with open(p,'r+b') as f:f.truncate(n)
    def register(self,path,info):
        rel=str(Path(path).relative_to(self.root))
        info=dict(info,path=rel,bytes=Path(path).stat().st_size,sha256=sha_file(path))
        self.db.execute('INSERT INTO assets VALUES (?,?)',(rel,json.dumps(info,ensure_ascii=False)))
        self.part_bytes+=info['bytes']
    def resolve(self,desc,check=True):
        p=safe_path(self.root,desc['path'])
        if not p.is_file():
            matches=[]
            for root in self.roots:
                matches.extend(root.rglob(Path(desc['path']).name) if root.exists() else [])
            p=next((x for x in matches if x.is_file() and x.stat().st_size==desc['bytes'] and sha_file(x)==desc['sha256']),None)
            if p is None:raise FileNotFoundError('请挂载包含此历史分片的输出：'+desc['path'])
        if check and (p.stat().st_size!=desc['bytes'] or sha_file(p)!=desc['sha256']):raise IOError('分片校验失败：'+str(p))
        return p
    def check_time(self):
        elapsed=time.monotonic()-self.started
        reserve=min(120,self.cfg.session_hours*3600*.05)
        if STOP or elapsed>=self.cfg.session_hours*3600-reserve:raise Pause('到达11小时内的保存时间点或收到停止请求')
        if time.monotonic()-self.last_check>5:
            self.last_check=time.monotonic()
            if shutil.disk_usage(self.root).free<2*1024**3:raise Pause('剩余磁盘不足2GiB，保存后暂停')
            if self.part_bytes>=self.cfg.max_output_gib*1024**3:raise Pause('本批达到输出容量预算；保存此版本并挂载后续跑')
    def due(self):return time.monotonic()-self.last_checkpoint>=self.cfg.checkpoint_seconds
    def checkpoint(self,flush,manifest,final=False):
        flush();self.put('generation',self.get('generation',0)+1);self.db.commit()
        self.db.execute('PRAGMA wal_checkpoint(TRUNCATE)')
        manifest()
        atomic_json(self.root/'local_run.json',dict(pipeline=self.marker,fingerprint=self.fingerprint,run_id=self.get('run_id'),generation=self.get('generation')))
        self.last_checkpoint=time.monotonic()
        if final:shutil.rmtree(self.cache,ignore_errors=True)
    def close(self):
        self.db.close()
        for sig,handler in self.old_handlers.items():signal.signal(sig,handler)

def hf_headers(url):
    token=os.environ.get('HF_TOKEN') or os.environ.get('HUGGING_FACE_HUB_TOKEN')
    h={'Accept-Encoding':'identity','User-Agent':'HCAM-preprocess/22'}
    if token and urlparse(url).hostname=='huggingface.co':h['Authorization']='Bearer '+token
    return h

def request_json(url,session):
    import requests
    error=None
    for attempt in range(3):
        session.check_time()
        try:
            r=requests.get(url,headers=hf_headers(url),timeout=(10,25));r.raise_for_status()
            return r.json(),r.links.get('next',{}).get('url')
        except (requests.RequestException,ValueError) as e:
            error=e
            if getattr(getattr(e,'response',None),'status_code',0) in (401,403,404):break
    raise SourceUnavailable(redact(error))

def source_plan(s,name,spec):
    key='source_plan:'+name
    if s.get(key):return s.get(key)
    s.log('[获取来源清单] '+name)
    repo=spec['repo'];rev=spec.get('revision','main')
    info,_=request_json('https://huggingface.co/api/datasets/'+repo+'/revision/'+quote(rev,safe=''),s)
    revision=info['sha'];files={}
    for prefix in spec.get('prefixes',['']):
        base='https://huggingface.co/api/datasets/'+repo+'/tree/'+revision
        url=base+('/'+quote(prefix.rstrip('/'),safe='/') if prefix else '')+'?recursive=true&limit=1000'
        while url:
            page,url=request_json(url,s)
            for x in page:
                path=x.get('path','')
                if x.get('type')!='file' or not path.endswith('.parquet'):continue
                if re.search(r'(?:^|[/_.-])(?:test|validation|valid|dev)(?:[/_.-]|$)',path,re.I):continue
                size=x.get('size',0);sha=(x.get('lfs') or {}).get('oid')
                files[path]=dict(path=path,size=size,sha256=sha if sha and re.fullmatch('[0-9a-f]{64}',sha) else None)
    if not files:raise SourceUnavailable(name+' 没有匹配的训练 Parquet 分片')
    ordered=sorted(files.values(),key=lambda x:x['path'])
    random.Random(s.cfg.seed+int(hashlib.sha256(name.encode()).hexdigest()[:8],16)).shuffle(ordered)
    plan=dict(repo=repo,revision=revision,files=ordered,fields=spec['fields'],primary=spec.get('primary',False))
    s.put(key,plan)  # 不在读取器里擅自提交；由写入器统一提交游标和数据。
    return plan

def validate_parquet(path,expected_size=0,expected_sha=None):
    n=Path(path).stat().st_size
    if n<12 or expected_size and n!=expected_size:raise BadShard('分片长度不符')
    with open(path,'rb') as f:
        head=f.read(4);f.seek(-8,2);tail=f.read(8)
    if head!=b'PAR1' or tail[-4:]!=b'PAR1':raise BadShard('PAR1头尾不符：文件不完整或响应不是Parquet')
    footer=int.from_bytes(tail[:4],'little')
    if footer<=0 or footer>n-12:raise BadShard('Parquet footer长度异常')
    if expected_sha and sha_file(path)!=expected_sha:raise BadShard('完整文件SHA256不匹配')
    import pyarrow.parquet as pq
    try:
        with pq.ParquetFile(path,pre_buffer=False) as pf:pass
    except Exception as e:raise BadShard('Parquet metadata无效：'+redact(e)) from e

def download_file(url,dest,s,expected_size=0,expected_sha=None):
    """只在完整文件校验通过后发布。Range恢复必须核对206及起始位置。"""
    import requests
    dest=Path(dest);part=dest.with_suffix(dest.suffix+'.download');dest.parent.mkdir(parents=True,exist_ok=True)
    if expected_size>s.cfg.max_shard_gib*1024**3:raise BadShard('分片大于下载预算：'+str(expected_size))
    if dest.exists():
        try:validate_parquet(dest,expected_size,expected_sha);return dest
        except BadShard:dest.unlink()
    last=None
    for attempt in range(3):
        s.check_time();offset=part.stat().st_size if part.exists() else 0
        if offset and expected_size and offset==expected_size:
            try:validate_parquet(part,expected_size,expected_sha);os.replace(part,dest);return dest
            except BadShard:part.unlink();offset=0
        headers=hf_headers(url)
        if offset:headers['Range']=f'bytes={offset}-'
        started=time.monotonic();last_log=started
        try:
            with requests.get(url,headers=headers,stream=True,timeout=(10,25)) as r:
                if r.status_code==416:part.unlink(missing_ok=True);continue
                r.raise_for_status()
                if r.headers.get('Content-Encoding','identity') not in ('','identity'):raise BadShard('服务器返回压缩HTTP内容，不能安全进行字节续传')
                if r.status_code==206:
                    cr=re.fullmatch(r'bytes (\d+)-(\d+)/(\d+|\*)',r.headers.get('Content-Range',''))
                    if not cr or int(cr[1])!=offset:raise BadShard('HTTP Content-Range起点不符')
                    total=int(cr[3]) if cr[3]!='*' else expected_size
                elif r.status_code==200:
                    offset=0;total=int(r.headers.get('Content-Length',0))
                else:raise BadShard('下载状态不是200/206')
                if total>s.cfg.max_shard_gib*1024**3:raise BadShard('分片超过大小预算')
                if expected_size and total and total!=expected_size:raise BadShard('远端长度与固定版本清单不同')
                n=offset
                with open(part,'ab' if offset else 'wb') as f:
                    for chunk in r.iter_content(1<<20):
                        s.check_time()
                        if time.monotonic()-started>s.cfg.download_seconds:raise SourceUnavailable('本分片下载超时，下一次继续')
                        n+=len(chunk)
                        if n>s.cfg.max_shard_gib*1024**3:raise BadShard('下载内容超出大小预算')
                        f.write(chunk)
                        if time.monotonic()-last_log>20:
                            print(f'[下载] {dest.name[:20]} {n/(1<<20):.0f}/{(expected_size or total)/(1<<20):.0f} MiB',flush=True);last_log=time.monotonic()
                    f.flush();os.fsync(f.fileno())
                if total and n!=total:raise BadShard('下载提前结束')
            validate_parquet(part,expected_size,expected_sha);os.replace(part,dest);return dest
        except Pause:raise
        except (requests.RequestException,BadShard,SourceUnavailable) as e:
            last=e
            if isinstance(e,BadShard):part.unlink(missing_ok=True)
            if getattr(getattr(e,'response',None),'status_code',0) in (401,403,404):break
            s.log('[分片重试] '+redact(e))
    if isinstance(last,BadShard):raise last
    raise SourceUnavailable('下载失败：'+redact(last))

PARQUET_WORKER = r'''
import os,sys,json,pickle,struct
os.environ['OPENBLAS_NUM_THREADS']='1'
import pyarrow as pa, pyarrow.parquet as pq
pa.set_cpu_count(1);pa.set_io_thread_count(1)
c=json.loads(sys.stdin.readline())
try:
 import resource
 current=int(open('/proc/self/statm').read().split()[0])*os.sysconf('SC_PAGE_SIZE')
 limit=current+int(c['memory_gib']*1024**3)
 resource.setrlimit(resource.RLIMIT_AS,(limit,limit))
except (ImportError,OSError,ValueError,PermissionError):pass
def emit(obj):
 b=pickle.dumps(obj,protocol=4);sys.stdout.buffer.write(struct.pack('<I',len(b)));sys.stdout.buffer.write(b);sys.stdout.buffer.flush()
try:
 with pq.ParquetFile(c['path'],pre_buffer=False,buffer_size=65536) as pf:
  names=pf.schema_arrow.names;cols=[x for x in c['fields'] if x in names]
  if c.get('primary'):
   body=next((x for x in cols if x!='score'),None);cols=[body]+(['score'] if 'score' in cols else []) if body else []
  if not cols:raise ValueError('请求的列不存在：'+str(names))
  for rg in range(c.get('group',0),pf.num_row_groups):
   offset=0
   for batch in pf.iter_batches(batch_size=c['batch'],columns=cols,row_groups=[rg],use_threads=False):
    for i in range(batch.num_rows):
     pos=dict(group=rg,row=offset+i+1)
     if rg==c.get('group',0) and offset+i<c.get('row',0):continue
     row={};oversize=False
     for j,k in enumerate(cols):
      value=batch.column(j)[i]
      if value.is_valid and (pa.types.is_string(value.type) or pa.types.is_large_string(value.type) or pa.types.is_binary(value.type) or pa.types.is_large_binary(value.type)):
       if value.as_buffer().size>c['max_record']:oversize=True;break
      row[k]=value.as_py()
     if oversize:emit((None,pos));continue
     encoded=pickle.dumps(row,protocol=4)
     emit((row if len(encoded)<=c['max_record'] else None,pos))
    offset+=batch.num_rows
   emit((None,dict(group=rg+1,row=0)))
 emit(('DONE',None))
except Exception as e:
 emit(('ERROR',type(e).__name__+': '+str(e)[:300]));sys.exit(2)
'''

def parquet_rows(path,fields,cursor,primary=False,batch=32,memory_gib=3.0,s=None):
    # Worker only decodes a verified LOCAL file. IPC is produced by our own worker, not dataset pickle.
    cfg=dict(path=str(path),fields=fields,group=cursor.get('group',0),row=cursor.get('row',0),
             primary=primary,batch=batch,memory_gib=memory_gib,max_record=16<<20)
    proc=subprocess.Popen([sys.executable,'-u','-c',PARQUET_WORKER],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,bufsize=0)
    proc.stdin.write((json.dumps(cfg)+'\n').encode());proc.stdin.close()
    sel=selectors.DefaultSelector();sel.register(proc.stdout,selectors.EVENT_READ)
    pending=bytearray();last=time.monotonic();done=False
    try:
        while True:
            if s:s.check_time()
            if not sel.select(.5):
                if time.monotonic()-last>120:raise BadShard('本地Parquet解码120秒无响应')
                if proc.poll() is not None:break
                continue
            b=os.read(proc.stdout.fileno(),1<<20)
            if not b:break
            pending.extend(b);last=time.monotonic()
            while len(pending)>=4:
                n=struct.unpack_from('<I',pending)[0]
                if n>20<<20:raise BadShard('单条记录超过IPC上限')
                if len(pending)<n+4:break
                event=pickle.loads(pending[4:n+4]);del pending[:n+4]
                row,pos=event
                if isinstance(row,str) and row=='ERROR':raise BadShard(pos)
                if isinstance(row,str) and row=='DONE':done=True
                else:yield row,pos
        if not done:raise BadShard('本地解码子进程异常退出，可能内存不足')
    finally:
        sel.close()
        if proc.poll() is None:proc.terminate()
        try:proc.wait(3)
        except subprocess.TimeoutExpired:proc.kill();proc.wait()
        proc.stdout.close()

def hf_rows(s,name,spec,key):
    plan=source_plan(s,name,spec);start=s.get(key,{});bad=0
    for fi in range(start.get('file',0),len(plan['files'])):
        s.check_time();desc=plan['files'][fi]
        url='https://huggingface.co/datasets/'+plan['repo']+'/resolve/'+plan['revision']+'/'+quote(desc['path'],safe='/')
        local=s.cache/(hashlib.sha256(url.encode()).hexdigest()[:24]+'.parquet')
        # 有界磁盘缓存，跨抽样/编码可复用少量已下载分片。
        cached=sorted(s.cache.glob('*.parquet'),key=lambda p:p.stat().st_mtime)
        size=sum(p.stat().st_size for p in cached)
        for p in cached:
            if size+desc['size']<=s.cfg.cache_gib*1024**3:break
            if p!=local:size-=p.stat().st_size;p.unlink()
        cursor={k:start.get(k,0) for k in ('group','row')} if fi==start.get('file',0) else {}
        try:
            download_file(url,local,s,desc['size'],desc.get('sha256'))
            for attempt in range(2):
                try:
                    with contextlib.closing(parquet_rows(local,plan['fields'],cursor,plan['primary'],batch=8 if 'image' in spec.get('kind','') else 64,memory_gib=3+attempt,s=s)) as rows:
                        for row,pos in rows:
                            cursor=pos;yield row,dict(file=fi,**pos)
                    break
                except BadShard:
                    if attempt:raise
            bad=0
        except BadShard as e:
            failure=dict(source=name,file=desc['path'],revision=plan['revision'],reason=redact(e),cursor=cursor)
            failures=s.get('failed_shards',[]);failures.append(failure);s.put('failed_shards',failures)
            s.log('[异常分片] '+name+' '+desc['path']+' '+redact(e));bad+=1
            if bad>=3:raise SourceUnavailable(name+' 连续3个分片失败，保留当前位置，下次重试')
        yield None,dict(file=fi+1,group=0,row=0)

def allocate(total,weights):
    if not weights or sum(weights)<=0:return [0]*len(weights)
    values=[int(total*x/sum(weights)) for x in weights]
    # Remainder goes to a nonzero category, never an absent optional source.
    values[max(i for i,w in enumerate(weights) if w>0)]+=total-sum(values)
    return values

@dataclass
class TextConfig:
    seed:int=42
    main_tokens:int=3_500_000_000
    tail_tokens:int=100_000_000
    val_tokens:int=1_000_000
    vocab_size:int=24_000
    tokenizer_sample_chars:int=24_000_000
    tokenizer_english_fraction:float=.10
    tokenizer_algorithm:str='bpe'  # bpe/unigram 均生成兼容的SentencePiece .model
    main_weights:tuple=(48,11.5,17,10,8,5,.5)
    tail_weights:tuple=(30,20,20,10,10,10)
    input_roots:tuple=()
    local_novels:tuple=()
    local_user:tuple=()
    min_chars:int=100
    max_doc_chars:int=80_000
    near_dedup:bool=True
    shard_tokens:int=8_000_000
    encode_batch:int=32
    workers:int=4
    local_commit_docs:int=256
    checkpoint_seconds:int=600
    session_hours:float=11.0
    max_output_gib:float=16.0
    max_shard_gib:float=4.0
    cache_gib:float=4.5
    download_seconds:int=900

CFG=configure(TextConfig(),'HCAM_TEXT_CONFIG_JSON')
ROOT=Path(os.environ.get('HCAM_TEXT_WORK_DIR','/kaggle/working/HCAM_TEXT_3p6B_V22' if IS_KAGGLE else 'HCAM_TEXT_3p6B_V22_work'))
MARKER='HCAM_TEXT_BPE_V22_LOCAL_VERIFIED'
CORE=('ultra','skypile','fineedu','cosmopedia','wiki','literature','user')
TAIL=('novels','law','medicine','biomedicine','mathematics','finance')
SPECS={
 'ultra':dict(repo='openbmb/Ultra-FineWeb',prefixes=['data/ultrafineweb_zh/'],fields=['content','text','score'],primary=True),
 'skypile':dict(repo='Skywork/SkyPile-150B',revision='refs/convert/parquet',fields=['text','content'],primary=True),
 'fineedu':dict(repo='opencsg/chinese-fineweb-edu',fields=['text','content','score'],primary=True),
 'cosmopedia':dict(repo='opencsg/chinese-cosmopedia',prefixes=['data/'],fields=['text','content'],primary=True),
 'wiki':dict(repo='HuggingFaceFW/finewiki',prefixes=['data/zhwiki/'],fields=['text','content'],primary=True),
 'literature':dict(repo='wikimedia/wikisource',prefixes=['20231201.zh/'],fields=['text'],primary=True),
 'novels':dict(repo='BAAI/IndustryCorpus2_literature_emotion',prefixes=['chinese/high/'],fields=['text','content'],primary=True),
 'law':dict(repo='BAAI/IndustryCorpus2_law_judiciary',prefixes=['chinese/high/'],fields=['text','content'],primary=True),
 'medicine':dict(repo='BAAI/IndustryCorpus2_medicine_health_psychology_traditional_chinese_medicine',prefixes=['chinese/high/'],fields=['text','content'],primary=True),
 'biomedicine':dict(repo='BAAI/IndustryCorpus2_biomedicine',prefixes=['chinese/high/'],fields=['text','content'],primary=True),
 'mathematics':dict(repo='BAAI/IndustryCorpus2_mathematics_statistics',prefixes=['chinese/high/'],fields=['text','content'],primary=True),
 'finance':dict(repo='BAAI/IndustryCorpus2_finance_economics',prefixes=['chinese/high/'],fields=['text','content'],primary=True),
 # 只用于词表的10%英文抽样；不挤占上面的3.5B+0.1B中文训练配额。
 'english':dict(repo='HuggingFaceFW/fineweb-edu',prefixes=['sample/10BT/'],fields=['text'],primary=True),
}

SPECIAL=('<用户>','<助手>','<换行>','<段落>')
CHINESE=re.compile(r'[\u3400-\u9fff]')
NOISE=re.compile(r'^(?:上一篇|下一篇|相关推荐|猜你喜欢|返回顶部|扫码关注|点击下载|客服热线|版权声明|广告位|商务合作|登录后评论|关注公众号|添加微信).{0,90}$')


def clean_text(raw):
    if not isinstance(raw,str):return ''
    text=html.unescape(raw).replace('\r\n','\n').replace('\r','\n')
    if len(text)>CFG.max_doc_chars:text=text[:CFG.max_doc_chars]
    protected={chr(0xe000+i):v for i,v in enumerate(SPECIAL)}
    for key,val in protected.items():text=text.replace(val,key)
    text=re.sub(r'<(?:script|style)\b[^>]*>.*?</(?:script|style)>','',text,flags=re.S|re.I)
    text=re.sub(r'<br\s*/?>','\n',text,flags=re.I)
    text=re.sub(r'</(?:p|div|section|article|h[1-6])\s*>','\n\n',text,flags=re.I)
    text=re.sub(r'<[^>\n]{1,500}>','',text)
    text=re.sub(r'[\u200b\u200e\u200f\u202a-\u202e\u2060\ufeff]','',text)
    lines=[re.sub(r'[ \t\u00a0\u3000]+',' ',line).strip() for line in text.split('\n')]
    text='\n'.join(line for line in lines if not NOISE.fullmatch(line))
    text=re.sub(r'\n{3,}','\n\n',text).strip()
    for key,val in protected.items():text=text.replace(key,val)
    return text


def good_text(text,source):
    if len(text)<CFG.min_chars or '\ufffd' in text or len(CHINESE.findall(text))<len(text)*.12:return False
    if re.search(r'(.)\1{18,}',text):return False
    chunks=re.findall(r'.{30,100}',text)
    if len(chunks)>12 and len(set(chunks))<len(chunks)*.55:return False
    if source=='novels':
        if re.search(r'(?:读后感|书评|读书笔记|读书感悟|图书推荐|书籍推荐)',text[:300]):return False
        chapter=bool(re.search(r'(?:第[一二三四五六七八九十百千万零〇\d]{1,10}[章回节]|楔子|序章)',text))
        dialogue=len(re.findall(r'[“「][^”」\n]{3,100}[”」]',text))
        return len(text)>=800 and (chapter or dialogue>=4)
    return True


def extract_text(row):
    for key in ('text','content','正文','body'):
        if isinstance(row.get(key),str):return row[key]
    messages=row.get('messages') or row.get('conversations')
    if isinstance(messages,list):
        pieces=[]
        for m in messages:
            role=m.get('role',m.get('from',''));v=m.get('content',m.get('value',''))
            if isinstance(v,str):pieces.append(('<用户>' if role in ('user','human') else '<助手>')+v)
        return '\n'.join(pieces)
    return ''


def local_text_rows(paths,cursor):
    files=[]
    for name in paths:
        p=Path(name);files+=sorted(p.rglob('*.txt'))+sorted(p.rglob('*.jsonl'))+sorted(p.rglob('*.parquet')) if p.is_dir() else [p]
    files=sorted(set(files))
    for index in range(cursor.get('file',0),len(files)):
        path=files[index];offset=cursor.get('offset',0) if index==cursor.get('file',0) else 0
        if path.suffix=='.parquet':
            inner=cursor if index==cursor.get('file',0) else {}
            for row,pos in parquet_rows(path,['text','content','messages','conversations'],inner,s=ACTIVE):yield row,dict(file=index,**pos)
        else:
            with open(path,'rb') as f:
                f.seek(offset)
                if path.suffix=='.jsonl':
                    while line:=f.readline((4<<20)+1):
                        if len(line)>4<<20:raise ValueError('本地JSONL单行超过4MiB')
                        if line.strip():yield json.loads(line),dict(file=index,offset=f.tell())
                else:
                    # 章节/段落优先切分；最多约16K字一段，不一次读入整本小说。
                    buffer=''
                    while True:
                        line=f.readline(48<<10)
                        if not line:
                            if buffer:yield {'text':buffer},dict(file=index,offset=f.tell())
                            break
                        while True:
                            try:decoded=line.decode('utf-8-sig',errors='strict');break
                            except UnicodeDecodeError as e:
                                if e.end==len(line) and 'unexpected end' in e.reason:
                                    extra=f.read(1)
                                    if extra:line+=extra;continue
                                raise
                        buffer+=decoded
                        if len(buffer)>=16_000 or (len(buffer)>=2000 and not line.strip()):
                            yield {'text':buffer},dict(file=index,offset=f.tell());buffer=''
        yield None,dict(file=index+1,offset=0,group=0,row=0)



class TokenWriter:
    def __init__(self,session,split):
        self.s=session;self.split=split;self.key='writer:'+split;self.state=session.get(self.key);self.file=None
        if self.state:
            path=session.root/self.state['partial'];path.parent.mkdir(parents=True,exist_ok=True)
            self.file=open(path,'r+b');self.file.truncate(self.state['tokens']*2);self.file.seek(0,2)
    def add(self,ids,source):
        import numpy as np
        if self.file is None:
            index=self.s.get('index:'+self.split,0);name=f'text/{self.split}-{index:06d}.bin'
            self.state=dict(path=name,partial=name+'.partial',tokens=0,source_mix={})
            path=self.s.root/self.state['partial'];path.parent.mkdir(parents=True,exist_ok=True);self.file=open(path,'w+b')
        self.file.write(np.asarray(ids,dtype='<u2').tobytes());self.state['tokens']+=len(ids)
        mix=self.state['source_mix'];mix[source]=mix.get(source,0)+len(ids)
    def sync(self):
        if self.file:
            self.file.flush();os.fsync(self.file.fileno());self.s.put(self.key,self.state)
    def seal(self):
        if not self.file:return
        self.sync();path=self.s.root/self.state['path'];partial=self.s.root/self.state['partial']
        path.unlink(missing_ok=True);os.link(partial,path)
        self.s.register(path,dict(split=self.split,tokens=self.state['tokens'],source_mix=self.state['source_mix']))
        self.s.put('index:'+self.split,self.s.get('index:'+self.split,0)+1);self.s.put(self.key,None);self.s.db.commit()
        self.file.close();self.file=None;partial.unlink();self.state=None



# 保守规范化：保留小数点、正负号、标点、大小写，不把不同数值合并。
def text_hash(text):
    canonical=re.sub(r'\s+',' ',unicodedata.normalize('NFKC',text)).strip()
    return hashlib.blake2b(canonical.encode(),digest_size=16).digest()

def source_rows(s,name,stage):
    local=CFG.local_novels if name=='novels' else CFG.local_user if name=='user' else ()
    for i,p in enumerate(local):
        key=f'{stage}:{name}:local:{i}'
        for row,pos in local_text_rows((p,),s.get(key,{})):yield row,key,pos
    if name=='user':return
    key=f'{stage}:{name}:hf'
    with contextlib.closing(hf_rows(s,name,SPECS[name],key)) as rows:
        for row,pos in rows:yield row,key,pos

def text_quality(text,name,row):
    if name=='english':
        return len(text)>=100 and len(re.findall('[A-Za-z]',text))>.45*len(text) and '\ufffd' not in text
    if not good_text(text,name):return False
    if name=='ultra':
        try:
            if row.get('score') is not None and float(row['score'])<.70:return False
        except (ValueError,TypeError):return False
    if re.search(r'[\x00-\x08\x0b\x0c\x0e-\x1f]',text):return False
    if len(re.findall(r'https?://|www\.',text))>max(3,len(text)//150):return False
    return True

def near_signature(text):
    import numpy as np
    compact=re.sub(r'\s+','',unicodedata.normalize('NFKC',text))
    n=len(compact)
    if n<400:return None
    step=max(1,(n-8)//96)
    grams=[compact[i:i+8] for i in range(0,max(1,n-7),step)][:128]
    hashes=b''.join(hashlib.blake2b(x.encode(),digest_size=8).digest() for x in grams)
    bits=np.unpackbits(np.frombuffer(hashes,dtype=np.uint8)).reshape(-1,64).sum(axis=0)
    h=int.from_bytes(np.packbits(bits*2>=len(grams)).tobytes(),'big')
    # Candidate verification uses additional sample hashes to reduce false matches.
    sketch=sorted(set(int.from_bytes(hashlib.blake2b(x.encode(),digest_size=4).digest(),'little') for x in grams))
    return h,n,struct.pack('<'+'I'*len(sketch),*sketch)

class TextPipeline:
    def __init__(self,s):
        self.s=s;self.counts=s.get('train_counts',{});self.val=s.get('val_count',0);self.docs=0
        self.rejected=s.get('rejected',{});self.sp=None;self.sample_active=None
        self.writers={k:TokenWriter(s,k) for k in ('train','val')}
        s.db.execute('CREATE TABLE IF NOT EXISTS seen(h BLOB PRIMARY KEY,split INTEGER) WITHOUT ROWID')
        s.db.execute('CREATE TABLE IF NOT EXISTS sample_seen(h BLOB PRIMARY KEY) WITHOUT ROWID')
        s.db.execute('CREATE TABLE IF NOT EXISTS near(h BLOB PRIMARY KEY,n INTEGER,b0 INTEGER,b1 INTEGER,b2 INTEGER,b3 INTEGER,sketch BLOB) WITHOUT ROWID')
        for i in range(4):s.db.execute(f'CREATE INDEX IF NOT EXISTS near{i} ON near(b{i})')
        weights=list(CFG.main_weights)
        if not CFG.local_user:weights[-1]=0
        self.targets=dict(zip(CORE,allocate(CFG.main_tokens,weights)))
        self.targets.update(zip(TAIL,allocate(CFG.tail_tokens,CFG.tail_weights)))
        self.targets=s.get('source_targets',self.targets);s.put('source_targets',self.targets);s.db.commit()
    def reject(self,why):self.rejected[why]=self.rejected.get(why,0)+1
    def commit(self):
        if self.sample_active:
            f=self.sample_active
            if not f.closed:f.flush();os.fsync(f.fileno());self.s.put('sample_bytes',f.tell())
        for w in self.writers.values():w.sync()
        self.s.put('train_counts',self.counts);self.s.put('val_count',self.val);self.s.put('rejected',self.rejected)
        self.s.db.commit();self.docs=0
        for w in self.writers.values():
            if w.state and w.state['tokens']>=CFG.shard_tokens:w.seal()
    def flush(self):
        self.commit()
        for w in self.writers.values():w.seal()
    def complete(self):return bool(self.sp and all(self.counts.get(k,0)==v for k,v in self.targets.items()) and self.val==CFG.val_tokens)
    def manifest(self):
        desc=self.s.descriptors();train=[x for x in desc if x['split']=='train'];val=[x for x in desc if x['split']=='val']
        tok=self.s.root/'tokenizer/tokenizer.model'
        if tok.is_file():shutil.copyfile(tok,self.s.root/'tokenizer.model')
        atomic_json(self.s.root/'text_asset_manifest.json',dict(format_version='HCAM-TEXT-BPE-v21',revision=MARKER,
            complete=self.complete(),vocab_size=CFG.vocab_size,tokenizer_path='tokenizer.model',tokenizer_sha256=sha_file(tok) if tok.is_file() else None,
            tokenizer_type='SentencePiece '+CFG.tokenizer_algorithm+'; Chinese-English; byte fallback; digits split',
            dtype='uint16-le',eos_between_documents=True,text_tokens=sum(x['tokens'] for x in train),text_shards=train,
            shard_tokens=[x['tokens'] for x in train],val_shards=val,val_tokens=sum(x['tokens'] for x in val),
            source_tokens=self.counts,source_targets=self.targets,main_target=CFG.main_tokens,tail_target=CFG.tail_tokens,
            sources={k:self.s.get('source_plan:'+k) for k in SPECS},failed_shards=self.s.get('failed_shards',[]),
            blocked_sources=self.s.get('blocked_sources',{}),rejections=self.rejected,
            dedup='NFKC+whitespace exact; conservative sampled SimHash + sketch Jaccard',catalog_dataset=None))
    def checkpoint(self,final=False):self.s.checkpoint(self.flush,self.manifest,final)
    def is_val(self,h):return int.from_bytes(h[:8],'little')%1000<2
    def tokenizer(self):
        import sentencepiece as spm
        out=self.s.root/'tokenizer';out.mkdir(exist_ok=True);model=out/'tokenizer.model'
        if model.exists():
            self.sp=spm.SentencePieceProcessor(model_file=str(model))
            if self.sp.vocab_size()!=CFG.vocab_size:raise ValueError('词表大小不符')
            return
        sample=self.s.root/'tokenizer_sample.txt'
        english=int(CFG.tokenizer_sample_chars*CFG.tokenizer_english_fraction)
        names=[k for k in self.targets if self.targets[k]>0]
        weights=[self.targets[k]**.5 for k in names]  # 温度采样，保留长尾术语
        quotas=dict(zip(names,allocate(CFG.tokenizer_sample_chars-english,weights)));quotas['english']=english
        with open(sample,'a+b') as f:
            f.truncate(self.s.get('sample_bytes',0));f.seek(0,2);self.sample_active=f
            try:
                for name,quota in quotas.items():
                    count=self.s.get('sample_count:'+name,0)
                    if count>=quota:continue
                    try:
                        with contextlib.closing(source_rows(self.s,name,'sample')) as rows:
                            for row,key,pos in rows:
                                self.s.check_time()
                                text=clean_text(extract_text(row)) if row else ''
                                if text_quality(text,name,row or {}):
                                    h=text_hash(text)
                                    if not self.is_val(h) and self.s.db.execute('INSERT OR IGNORE INTO sample_seen VALUES (?)',(h,)).rowcount:
                                        text=text[:quota-count]
                                        for off in range(0,len(text),1000):f.write((text[off:off+1000].replace('\n',' ')+'\n').encode())
                                        count+=len(text)
                                self.s.put(key,pos);self.s.put('sample_count:'+name,count);self.docs+=1
                                if self.docs>=CFG.local_commit_docs:self.commit()
                                if self.s.due():self.checkpoint()
                                self.s.panel.update('中英文BPE抽样',sum(self.s.get('sample_count:'+k,0) for k in quotas),CFG.tokenizer_sample_chars,name)
                                if count>=quota:break
                    except SourceUnavailable as e:self.s.log('[抽样来源暂缓] '+name+' '+redact(e))
                    self.commit()
            finally:self.commit();self.sample_active=None
        counts={k:self.s.get('sample_count:'+k,0) for k in quotas}
        if sample.stat().st_size<1_000_000:raise Pause('有效分词样本不足1MB，已保存，下次续跑')
        if sum(v>=10000 for v in counts.values())<3:raise Pause('至少需要3个来源的分词样本，已保存，下次续跑')
        if CFG.tokenizer_english_fraction and counts.get('english',0)<min(english,100000):raise Pause('英文词表样本不足，已保存；网络恢复后继续')
        prefix=out/'training'
        params=dict(input=str(sample),model_prefix=str(prefix),model_type=CFG.tokenizer_algorithm,vocab_size=CFG.vocab_size,
            unk_id=0,bos_id=1,eos_id=2,pad_id=3,user_defined_symbols=list(SPECIAL),byte_fallback=True,
            character_coverage=.9995,normalization_rule_name='identity',remove_extra_whitespaces=False,add_dummy_prefix=False,
            split_by_unicode_script=True,split_by_whitespace=True,split_by_number=True,split_digits=True,
            input_sentence_size=0,shuffle_input_sentence=False,max_sentence_length=8192,num_threads=min(CFG.workers,os.cpu_count() or 2),hard_vocab_limit=True,minloglevel=2)
        self.commit()
        with open(self.s.root/'tokenizer_training.log','a') as log:
            proc=subprocess.Popen([sys.executable,'-c','import json,sys,sentencepiece as s;s.SentencePieceTrainer.train(**json.load(sys.stdin))'],stdin=subprocess.PIPE,stdout=log,stderr=log,text=True)
            proc.stdin.write(json.dumps(params));proc.stdin.close()
            try:
                while proc.poll() is None:self.s.check_time();time.sleep(.5)
                if proc.returncode:
                    tail=(self.s.root/'tokenizer_training.log').read_text(errors='replace')[-1200:]
                    raise Pause('分词器训练未完成，样本保留；日志末尾：'+tail)
            finally:
                if proc.poll() is None:
                    proc.terminate()
                    try:proc.wait(3)
                    except subprocess.TimeoutExpired:proc.kill();proc.wait()
        sp=spm.SentencePieceProcessor(model_file=str(prefix.with_suffix('.model')))
        tests=['捕蝇草会捕食昆虫。','English words and 中文混合 2026-10-20，3.14159。','罕见字：𠮷，符号🙂 αβ。','A  B<换行>第二行']
        report=[]
        for text in tests:
            ids=sp.encode(text);decoded=sp.decode(ids)
            if decoded!=text or 0 in ids:raise ValueError('分词往返校验未通过：'+repr(text))
            report.append(dict(text=text,pieces=sp.encode(text,out_type=str),roundtrip=True))
        atomic_json(out/'tokenizer_check.json',dict(algorithm=CFG.tokenizer_algorithm,sample_chars=counts,vocab_size=sp.vocab_size(),checks=report))
        os.replace(prefix.with_suffix('.vocab'),out/'tokenizer.vocab');os.replace(prefix.with_suffix('.model'),model)
        self.sp=sp;self.checkpoint()
    def near_duplicate(self,sig):
        if not sig:return False
        h,n,sketch=sig;bands=[(h>>(16*i))&65535 for i in range(4)]
        rows=self.s.db.execute('SELECT h,n,sketch FROM near WHERE (b0=? OR b1=? OR b2=? OR b3=?) AND n BETWEEN ? AND ? LIMIT 96',(*bands,int(n*.97),int(n*1.03)+1))
        a=set(struct.unpack('<'+'I'*(len(sketch)//4),sketch))
        for old,_,other in rows:
            if (h^int.from_bytes(old,'little')).bit_count()>3:continue
            b=set(struct.unpack('<'+'I'*(len(other)//4),other))
            if len(a&b)/max(1,len(a|b))>=.90:return True
        return False
    def encode_batch(self,batch,name,only_val=False):
        records=[];texts=[];batch_hashes=set()
        for row,key,pos in batch:
            if not row:continue
            text=clean_text(extract_text(row))
            if not text_quality(text,name,row):self.reject('quality');continue
            h=text_hash(text);is_val=self.is_val(h)
            if only_val and not is_val:continue
            if h in batch_hashes or self.s.db.execute('SELECT 1 FROM seen WHERE h=?',(h,)).fetchone():self.reject('exact_duplicate');continue
            batch_hashes.add(h)
            records.append((h,is_val,text));texts.append(text.replace('\n\n','<段落>').replace('\n','<换行>'))
        # Native SentencePiece batch parallelism; no large Python process copies.
        encoded=self.sp.encode(texts,out_type=int,num_threads=min(CFG.workers,os.cpu_count() or 2)) if texts else []
        for (h,is_val,text),ids in zip(records,encoded):
            sig=near_signature(text) if CFG.near_dedup else None
            if self.near_duplicate(sig):self.reject('near_duplicate');continue
            remain=CFG.val_tokens-self.val if is_val else self.targets[name]-self.counts.get(name,0)
            if remain<=0:continue
            ids=ids[:max(0,remain-1)]+[self.sp.eos_id()]
            self.writers['val' if is_val else 'train'].add(ids,name)
            self.s.db.execute('INSERT INTO seen VALUES (?,?)',(h,int(is_val)))
            if sig:
                nh,n,sketch=sig;bands=[(nh>>(16*i))&65535 for i in range(4)]
                self.s.db.execute('INSERT OR IGNORE INTO near VALUES (?,?,?,?,?,?,?)',(nh.to_bytes(8,'little'),n,*bands,sketch))
            if is_val:self.val+=len(ids)
            else:self.counts[name]=self.counts.get(name,0)+len(ids)
        for row,key,pos in batch:self.s.put(key,pos)
        self.docs+=len(batch)
        if self.docs>=CFG.local_commit_docs:self.commit()
    def consume(self,name,stage,only_val=False,budget=None):
        batch=[];initial=self.counts.get(name,0)
        with contextlib.closing(source_rows(self.s,name,stage)) as rows:
            try:
                for item in rows:
                    self.s.check_time();batch.append(item)
                    if len(batch)>=CFG.encode_batch:
                        self.encode_batch(batch,name,only_val);batch=[]
                        self.s.panel.update('文本词元',sum(self.counts.values()),CFG.main_tokens+CFG.tail_tokens,f'{name}；验证 {self.val:,}')
                        if self.s.due():self.checkpoint()
                        if (self.val>=CFG.val_tokens if only_val else self.counts.get(name,0)>=self.targets[name]):break
                        if budget and self.counts.get(name,0)-initial>=budget:break
            finally:
                if batch:self.encode_batch(batch,name,only_val)
    def run(self):
        self.checkpoint();self.tokenizer();blocked={}
        # 轮换处理各来源的一部分，使11小时途中暂停也能留下多样化资产。
        for budget in (10_000_000,None):
            for name,target in self.targets.items():
                if self.counts.get(name,0)>=target or name in blocked:continue
                try:self.consume(name,'encode',budget=budget)
                except SourceUnavailable as e:blocked[name]=redact(e);self.s.log('[来源暂缓] '+name+' '+redact(e))
                self.commit();self.s.put('blocked_sources',blocked);self.checkpoint()
        if self.val<CFG.val_tokens:
            for name in ('fineedu','wiki','ultra'):
                try:self.consume(name,'validation_fill',True)
                except SourceUnavailable as e:self.s.log('[验证补充暂缓] '+name+' '+redact(e))
                if self.val>=CFG.val_tokens:break
        self.checkpoint(final=True)
        self.s.panel.update('文本完成' if self.complete() else '本次已保存，尚未凑足',sum(self.counts.values()),CFG.main_tokens+CFG.tail_tokens,'不会用重复文本填充配额',True)

def main():
    dependencies()
    print('[V22] 本地完整Parquet校验；24K中英文子词；3.5B+0.1B；单次不超过11小时。',flush=True)
    print('[使用] Kaggle CPU + Internet On；Save Version → Save & Run All，保存输出。每10分钟落盘；续跑挂载上一版输出。',flush=True)
    s=Session(ROOT,CFG,MARKER);p=TextPipeline(s)
    try:p.run()
    except (Pause,SourceUnavailable) as e:
        p.checkpoint(final=True);s.panel.update('已保存暂停',sum(p.counts.values()),CFG.main_tokens+CFG.tail_tokens,redact(e),True)
    except Exception as e:
        p.checkpoint(final=True)
        atomic_json(s.root/'last_error.json',dict(type=type(e).__name__,error=redact(e)))
        print('[异常已保存] '+type(e).__name__+': '+redact(e),flush=True)
        raise
    finally:s.close()

if __name__=='__main__':main()

