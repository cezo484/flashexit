"""Assemble the FlashExit demo video: PIL slides + Piper narration, muxed to MP4.

Timeline (120 s total):
  title 6 | problem 13 | idea 19 | order 18 | trigger 8 | reaction 8 |
  exit 11 | safeguards 16 | bothways 9 | closing 12

Narration offsets: s1 0.8 | s2 6.8 | s3 19.8 | s4 38.8 | s5 56.8 |
  s6 64.8 | s7 72.8 | s8 83.8 | s9 99.8 | s10 108.8
Narration durations: s1 4.70 | s2 11.62 | s3 17.28 | s4 16.02 | s5 6.36 |
  s6 6.87 | s7 9.46 | s8 14.89 | s9 7.63 | s10 9.55
"""
import os
import subprocess

BASE = os.path.dirname(os.path.abspath(__file__))
SEG_DIR = os.path.join(BASE, "segments")
os.makedirs(SEG_DIR, exist_ok=True)

W, H = 1920, 1080
FPS = 24

# (name, slide file, duration)
SEGMENTS = [
    ("title", "title.png", 6.0),
    ("problem", "problem.png", 13.0),
    ("idea", "idea.png", 19.0),
    ("order", "order.png", 18.0),
    ("trigger", "trigger.png", 8.0),
    ("reaction", "reaction.png", 8.0),
    ("exit", "exit.png", 11.0),
    ("safeguards", "safeguards.png", 16.0),
    ("bothways", "bothways.png", 9.0),
    ("closing", "closing.png", 12.0),
]

NARRATION = [  # (file, offset_seconds)
    ("s1.wav", 0.8),
    ("s2.wav", 6.8),
    ("s3.wav", 19.8),
    ("s4.wav", 38.8),
    ("s5.wav", 56.8),
    ("s6.wav", 64.8),
    ("s7.wav", 72.8),
    ("s8.wav", 83.8),
    ("s9.wav", 99.8),
    ("s10.wav", 108.8),
]


def run(cmd):
    print(" ".join(cmd[:6]), "...", flush=True)
    subprocess.run(cmd, check=True)


def encode_segment(i, name, slide, dur):
    src = os.path.join(BASE, "slides", slide)
    out = os.path.join(SEG_DIR, f"{i:02d}-{name}.mp4")
    cmd = ["ffmpeg", "-y", "-v", "error",
           "-loop", "1", "-i", src, "-t", f"{dur:.2f}",
           "-vf", f"fps={FPS},format=yuv420p",
           "-c:v", "libx264", "-preset", "medium", "-crf", "20",
           "-pix_fmt", "yuv420p", "-an", out]
    run(cmd)
    return out


def build_audio(total):
    narr = os.path.join(BASE, "narration")
    inputs, filt = [], []
    for i, (fn, off) in enumerate(NARRATION):
        inputs += ["-i", os.path.join(narr, fn)]
        filt.append(f"[{i}]adelay={int(off * 1000)}:all=1[a{i}]")
    filt.append("".join(f"[a{i}]" for i in range(len(NARRATION))) +
                f"amix=inputs={len(NARRATION)}:duration=longest:normalize=0,"
                f"apad=whole_dur={total:.1f},atrim=0:{total:.1f}[aout]")
    cmd = ["ffmpeg", "-y", "-v", "error"] + inputs + [
        "-filter_complex", ";".join(filt),
        "-map", "[aout]", "-ar", "44100", "-ac", "2",
        os.path.join(BASE, "audio.wav")]
    run(cmd)
    print("audio built")


def main():
    total = sum(d for _, _, d in SEGMENTS)
    print(f"segments: {len(SEGMENTS)}, total video: {total:.2f}s")
    paths = []
    for i, (name, slide, dur) in enumerate(SEGMENTS):
        paths.append(encode_segment(i, name, slide, dur))
    concat_path = os.path.join(BASE, "concat.txt")
    with open(concat_path, "w") as f:
        for p in paths:
            f.write(f"file '{p}'\n")
    build_audio(total)
    cmd = ["ffmpeg", "-y", "-v", "error",
           "-f", "concat", "-safe", "0", "-i", concat_path,
           "-i", os.path.join(BASE, "audio.wav"),
           "-c:v", "libx264", "-preset", "medium", "-crf", "20",
           "-pix_fmt", "yuv420p",
           "-c:a", "aac", "-b:a", "128k",
           "-t", f"{total:.2f}",
           os.path.join(BASE, "flashexit-demo.mp4")]
    run(cmd)
    print(f"DONE: flashexit-demo.mp4 ({total:.2f}s)")


if __name__ == "__main__":
    main()
