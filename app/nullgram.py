"""Nullgram's starter: the app is nullgram_app.py, imported from here -- Python keeps an imported module's
compiled copy in __pycache__ and reads that, but compiles the file it is started with anew every time
(the app's 2000 lines: ~200 ms of each start on an M4 core, and again in each picture helper).

  python3 nullgram.py [--test-dc]      (--test-dc: Telegram's test servers, a throwaway account;
                                       NULLGRAM_TEST_PHONE=99966XYYYY signs in there by itself)
  python3 nullgram.py --imager         (a picture helper: nullgram_app.Imager starts two)

The scripts that find the running app look for this name (pgrep -f 'nullgram/nullgram.py')."""
import os
import sys

# ARM's little cores (Cortex-A53, A35, A55, A510, A520): /proc/cpuinfo's "CPU part"
LITTLE = {"0xd03", "0xd04", "0xd05", "0xd46", "0xd80"}


def big_cores():
	"""The cores that are not little ones, when the phone has both (else None). The S10's kernel has no
	cpufreq and gives every core the same capacity (1024), so the scheduler put the UI thread on one of
	its four Cortex-A55s as readily as on an A75 or M4 (the desk's rows made end to end: 4.5 s on an A55,
	3.2 on an A75, 1.3 on an M4): one flick fast, the next slow. (Timed instead, on cores just woken,
	the A55s came out as fast as the M4s now and then.)"""
	part, parts = None, {}
	try:
		with open("/proc/cpuinfo") as f:
			for line in f:
				k, _, v = line.partition(":")
				k, v = k.strip(), v.strip()
				if k == "processor":
					part = int(v)
				elif k == "CPU part" and part is not None:
					parts[part] = v.lower()
	except (OSError, ValueError):
		return None
	big = {c for c, v in parts.items() if v not in LITTLE}
	return big if 0 < len(big) < len(parts) else None


# NULLGRAM_CPUS: off (as the kernel schedules it), or the cores to hold it to (e.g. 6,7); else the big ones.
# Set before the imports (PySide's alone ~0.5 s): set later, in main(), they ran on whichever core the
# shell's starter had, an A55 as often as not -- from the tap to the first frame 2.0-3.9 s, now 1.3-2.4.
# (A picture helper keeps the app's: on the desk, taskset's.)
want = os.environ.get("NULLGRAM_CPUS", "")
cpus = None if want == "off" or "--imager" in sys.argv else {int(c) for c in want.split(",")} if want else big_cores()
if cpus:
	try:
		os.sched_setaffinity(0, cpus)
	except OSError:
		pass

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import nullgram_app  # noqa: E402

if __name__ == "__main__":
	nullgram_app.imager() if "--imager" in sys.argv else nullgram_app.main()
