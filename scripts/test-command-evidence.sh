#!/usr/bin/env bash
set -euo pipefail
export TOOLKIT_COMMAND_EVIDENCE_PREFIX=TOOLKIT_TEST_COMMAND
for prerequisite in python3 jq base64 wc bash; do
  command -v "$prerequisite" >/dev/null || { echo "warm Cargo evidence fixture: missing $prerequisite" >&2; exit 127; }
done
here=$(cd "$(dirname "$0")" && pwd -P)
helper=${1:-$here/command-evidence.sh}
[[ $# -le 1 && $helper == /* && -f $helper ]] || exit 2
invocation=("$BASH" "$helper")
if [[ $# == 1 ]]; then
 [[ -x $helper ]] || exit 2
 invocation=("$helper")
fi
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
for invalid in '' lower 'HAS-DASH' $'LINE\nBREAK' $'\xc3\x89' "$(printf 'A%.0s' {1..65})"; do
 result=0
 TOOLKIT_COMMAND_EVIDENCE_PREFIX=$invalid "${invocation[@]}" "$fixture/refused.raw" -- \
  bash -c 'printf entered > "$1"' rejected-prefix "$fixture/refused-command-ack" \
  > "$fixture/refusal.out" 2> "$fixture/refusal.err" || result=$?
 [[ $result == 2 && ! -s $fixture/refusal.out && ! -e $fixture/refused.raw && ! -e $fixture/refused-command-ack ]]
 grep -Fx 'command evidence: explicit uppercase frame prefix required (1..64 bytes)' "$fixture/refusal.err"
done
printf '%s\n' 'PASS6 prefix refusals before original command or log creation'
longest=$(printf 'A%.0s' {1..64})
TOOLKIT_COMMAND_EVIDENCE_PREFIX=$longest "${invocation[@]}" "$fixture/longest.raw" -- \
 bash -c 'printf "boundary\\000\\377"' > "$fixture/longest.frame" 2> "$fixture/longest.err"
[[ ! -s $fixture/longest.err && $(head -n 1 "$fixture/longest.frame") == "${longest}_BEGIN_V1" &&
 $(tail -n 1 "$fixture/longest.frame") == "${longest}_END_V1" ]]
printf 'boundary\000\377' > "$fixture/longest.expected"
cmp "$fixture/longest.expected" "$fixture/longest.raw"
printf '%s\n' 'PASS maximum64-byte prefix with exact binary stdout'
python3 - "$helper" "$fixture/cases" "$#" "$BASH" <<'PYTHON'
import base64,json,os,pathlib,subprocess,sys
helper=pathlib.Path(sys.argv[1]).resolve(); fixture=pathlib.Path(sys.argv[2]).resolve(); fixture.mkdir(exist_ok=False)
bash=sys.argv[4];direct=sys.argv[3]=='1'
provider=os.environ['PATH']
(fixture/'bin').mkdir();cmd=fixture/'original-command';cmd.write_text('#!/usr/bin/python3\nimport os,sys\nopen(os.environ["ACK"],"w").write("original command entered")\nsys.stdout.buffer.write(b\'{"reason":"compiler-artifact","fresh":false,"filenames":["sandbox/file"],"features":[]}\\n\\x00\\xffpartial\\n\')\nsys.stderr.write("original command stderr\\n")\nsys.exit(int(os.environ.get("ORIGINAL_STATUS","0")))\n');cmd.chmod(0o700)
# Actual system Python provider is selected explicitly; no compiler invocation.
cmd.write_text(cmd.read_text().replace('#!/usr/bin/python3','#!'+sys.executable))
held_stdout=b'{"reason":"compiler-artifact","fresh":false,"filenames":["sandbox/file"],"features":[]}\n\x00\xffpartial\n'
results=[]
def parse(data):
 lines=data.decode().splitlines();assert lines[0]=='TOOLKIT_TEST_COMMAND_BEGIN_V1' and lines[-1]=='TOOLKIT_TEST_COMMAND_END_V1'
 argv_end=lines.index('TOOLKIT_TEST_COMMAND_ARGV_END_V1');stdout_end=lines.index('TOOLKIT_TEST_COMMAND_STDOUT_END_V1')
 argv=base64.b64decode(''.join(lines[3:argv_end]),validate=True);stdout=base64.b64decode(''.join(lines[argv_end+3:stdout_end]),validate=True)
 assert len(argv)==int(lines[1].split(':')[1]) and len(stdout)==int(lines[argv_end+1].split(':')[1])
 return json.loads(argv),stdout,int(lines[stdout_end+1].split(':')[1])
def run(name,original=0,fault=None,closed=False):
 d=fixture/name;d.mkdir();env={**os.environ,'PATH':str(fixture/'bin')+':'+provider,'ACK':str(d/'ack'),'ORIGINAL_STATUS':str(original),'TMPDIR':str(d)}
 for x in ['base64','jq','rm']:
  f=fixture/'bin'/x
  if f.exists():f.unlink()
 if fault:
  tool,status=fault;f=fixture/'bin'/tool;f.write_text('#!/bin/sh\necho "original '+tool+' native failure" >&2\nexit '+str(status)+'\n');f.chmod(0o700)
 command_args=[str(cmd),'space arg','','line\nbreak']
 argv=([str(helper)] if direct else [bash,str(helper)])+[str(d/'cargo.raw'),'--']+command_args
 if closed:
  p=subprocess.Popen(argv,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE);p.stdout.close();err=p.stderr.read();code=p.wait(timeout=10);out=b''
 else:
  p=subprocess.run(argv,env=env,capture_output=True);code,out,err=p.returncode,p.stdout,p.stderr
 (d/'stdout').write_bytes(out);(d/'stderr').write_bytes(err);(d/'status').write_text(str(code)+'\n')
 if fault and fault[0]=='jq':assert code==2 and not (d/'ack').exists() and not (d/'cargo.raw').exists()
 else:
  assert (d/'ack').read_text()=='original command entered';assert b'original command stderr' in err
  if fault and fault[0]=='base64':
   assert code==(original or fault[1]);assert b'log publication failed native=42' in err and b'TOOLKIT_TEST_COMMAND_END_V1' not in out
  elif closed:assert code==original and b'log publication failed native=' in err
  else:
   captured,raw,status=parse(out);assert captured==command_args and raw==held_stdout and (d/'cargo.raw').read_bytes()==held_stdout and status==original
   assert len(raw)==len(held_stdout)
   if fault and fault[0]=='rm':assert code==(original or fault[1]) and b'metadata cleanup failed native=43' in err
   else:assert code==original
 # Fixture owns this private TMPDIR. Failed native cleanup must retain actual
 # metadata until this original child is acknowledged terminal; inspect it first.
 leftovers=[x for x in d.iterdir() if x.is_dir() and x.name.startswith('tmp.')]
 if fault and fault[0]=='rm':
  assert len(leftovers)==1 and (leftovers[0]/'argv.json').is_file()
  assert ('path='+str(leftovers[0])).encode() in err
 else:assert not leftovers
 results.append({'name':name,'native_status':code,'original_status':original,'fault':fault,'closed_native_pipe':closed})
run('success');run('original37',37);run('publication42',fault=('base64',42));run('original37-publication42',37,('base64',42));run('jq2-no-command',fault=('jq',2));run('original37-closed-native-pipe',37,closed=True);run('cleanup43',fault=('rm',43));run('original37-cleanup43',37,('rm',43))
(fixture/'results.json').write_text(json.dumps(results,indent=2)+'\n');print('PASS8 controls: exact raw bytes/argv/status, partial failed stdout, publication42, jq2 no-command, actual closed pipe, cleanup43 with original37 retained')
PYTHON

python3 - "$helper" "$fixture/closed" "$BASH" <<'CLOSED_STDERR'
import base64,errno,json,os,pathlib,subprocess,sys
helper=pathlib.Path(sys.argv[1]).resolve();case_root=pathlib.Path(sys.argv[2]).resolve();case_root.mkdir(exist_ok=False)
bash=sys.argv[3];provider=os.environ['PATH'];results=[]
held=b'{"reason":"held-closed-stderr-command"}\n'
for tool,fault_status in [('base64',42),('rm',43)]:
 for original in [37,0]:
  d=case_root/(tool+'-original'+str(original));d.mkdir();(d/'bin').mkdir()
  fault=d/'bin'/tool;fault.write_text('#!/bin/sh\nprintf "original '+tool+' failure reached\\n" > "$FAULT_ACK"\nexit '+str(fault_status)+'\n');fault.chmod(0o700)
  env={**os.environ,'PATH':str(d/'bin')+':'+provider,'TMPDIR':str(d),'ACK':str(d/'ack'),'FAULT_ACK':str(d/'fault-ack'),'ORIGINAL':str(original)}
  wrapper=r'''helper_body=$(cat "$1" && printf '.') || exit $?
helper_body=${helper_body%.}; shift
original_silent_command() {
  if : >&2; then return 98; fi
  printf "original acknowledged stderr EBADF" > "$ACK"
  printf '%s\n' '{"reason":"held-closed-stderr-command"}'
  return "$ORIGINAL"
}
exec 2>&-
eval "$helper_body"
'''
  p=subprocess.run([bash,'-c',wrapper,'original-closed-stderr-owner',str(helper),str(d/'cargo.raw'),'--','original_silent_command'],env=env,capture_output=True)
  (d/'stdout').write_bytes(p.stdout);(d/'stderr').write_bytes(p.stderr);(d/'status').write_text(str(p.returncode)+'\n')
  assert (d/'ack').read_text()=='original acknowledged stderr EBADF' and (d/'fault-ack').read_text()=='original '+tool+' failure reached\n'
  assert (d/'cargo.raw').read_bytes()==held and not p.stderr
  if tool=='rm':
   lines=p.stdout.decode().splitlines();assert lines[0]=='TOOLKIT_TEST_COMMAND_BEGIN_V1' and lines[-1]=='TOOLKIT_TEST_COMMAND_END_V1'
   a=lines.index('TOOLKIT_TEST_COMMAND_ARGV_END_V1');b=lines.index('TOOLKIT_TEST_COMMAND_STDOUT_END_V1')
   aj=base64.b64decode(''.join(lines[3:a]),validate=True);raw=base64.b64decode(''.join(lines[a+3:b]),validate=True)
   assert len(aj)==int(lines[1].split(':')[1]) and json.loads(aj)==['original_silent_command']
   assert raw==held and len(raw)==int(lines[a+1].split(':')[1]) and int(lines[b+1].split(':')[1])==original
  expected=original or fault_status
  results.append({'tool':tool,'original_status':original,'independent_fault_status':fault_status,'native_helper_status':p.returncode,'expected_status':expected,'actual_original_stderr_EBADF':True,'cause_channel_available':False})
(case_root/'results.json').write_text(json.dumps(results,indent=2)+'\n');print(json.dumps(results))
assert all(x['native_helper_status']==x['expected_status'] for x in results),'original/native failure replaced when diagnostic FD2 unavailable'

print("PASS4 closed-stderr controls: actual original EBADF acknowledgment; original37 or native publication42/cleanup43 retained")
CLOSED_STDERR
