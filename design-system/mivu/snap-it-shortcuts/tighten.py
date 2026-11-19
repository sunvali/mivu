import re,subprocess,sys
src,dst,head=sys.argv[1],sys.argv[2],float(sys.argv[3])
KEEP=0.5  # seconds of each still stretch that survive
# optional 4th argument: extra ranges to drop, in source seconds, e.g. "3.2-6.6,9-10" (for idle stretches that still animate)
extra=[tuple(float(x)-head for x in r.split('-')) for r in sys.argv[4].split(',')] if len(sys.argv)>4 else []
out=subprocess.run(['ffmpeg','-hide_banner','-ss',str(head),'-i',src,'-vf','freezedetect=n=0.006:d=0.7','-an','-f','null','-'],capture_output=True,text=True).stderr
starts=[float(x) for x in re.findall(r'freeze_start: ([\d.]+)',out)]
ends=[float(x) for x in re.findall(r'freeze_end: ([\d.]+)',out)]
dur=float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','csv=p=0',src]))-head
ends+= [dur]*(len(starts)-len(ends))
cuts=[f"between(t,{s+KEEP:.3f},{e-0.05:.3f})" for s,e in zip(starts,ends) if e-s>KEEP+0.1 and e<dur-0.01]
cuts+=[f"between(t,{a:.3f},{b:.3f})" for a,b in extra]
# the last still stretch is the result: hold it 1.6s
if starts and ends[-1]>=dur-0.01: cuts.append(f"gte(t,{starts[-1]+1.6:.3f})")
sel="not("+"+".join(cuts)+")" if cuts else "1"
vf=f"select='{sel}',setpts=N/30/TB,scale=600:-2:flags=lanczos,format=yuv420p"
subprocess.check_call(['ffmpeg','-v','error','-y','-ss',str(head),'-i',src,'-vf',vf,'-an','-r','30','-c:v','libx265','-crf','27','-preset','slow','-tag:v','hvc1','-movflags','+faststart',dst])
print(dst, len(cuts),'cuts', subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration,size','-of','csv=p=0',dst],text=True).strip())
