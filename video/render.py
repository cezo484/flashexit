"""Slide renderer for the FlashExit demo video (1920x1080, PIL).
Adapted from the HSK AgentSubs renderer (same workspace).
No em-dashes anywhere in on-screen text. No real names; author is cezo484.
All transaction hashes, addresses and latencies are the real testnet runs
of 23 Nov 2026 (see deployments/testnet-20261124.env).
"""
from PIL import Image, ImageDraw
import os

W, H = 1920, 1080

BG = (13, 17, 23)
BG2 = (22, 27, 34)
PANEL = (22, 27, 34)
BORDER = (48, 54, 61)
TERM_BG = (13, 17, 23)
TEXT = (230, 237, 243)
MUTED = (139, 148, 158)
FAINT = (100, 116, 139)
ACCENT = (88, 166, 255)
GREEN = (63, 185, 80)
GREEN_BRIGHT = (86, 211, 100)
YELLOW = (210, 153, 34)
RED = (248, 81, 73)
WHITE = (255, 255, 255)

FONT_DIR = "/usr/share/fonts/truetype/dejavu"
_fonts = {}


def font(name, size):
    key = (name, size)
    if key not in _fonts:
        from PIL import ImageFont
        _fonts[key] = ImageFont.truetype(os.path.join(FONT_DIR, name), size)
    return _fonts[key]


def sans(size, bold=False):
    return font("DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf", size)


def mono(size, bold=False):
    return font("DejaVuSansMono-Bold.ttf" if bold else "DejaVuSansMono.ttf", size)


def canvas():
    return Image.new("RGB", (W, H), BG)


def wrap(draw, text, fnt, max_w):
    words = text.split()
    lines, cur = [], ""
    for w in words:
        trial = (cur + " " + w).strip()
        if draw.textlength(trial, font=fnt) <= max_w:
            cur = trial
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def rounded(draw, box, radius, fill=None, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def badge(draw, x, y, text, fg, bg, fnt, pad_x=16, pad_y=8):
    w = int(draw.textlength(text, font=fnt)) + 2 * pad_x
    h = fnt.size + 2 * pad_y
    rounded(draw, [x, y, x + w, y + h], h // 2, fill=bg)
    draw.text((x + pad_x, y + pad_y - 2), text, font=fnt, fill=fg)
    return w


def footer(draw, left="FlashExit  ·  testnet only", right="Reactive Omni Buildathon"):
    f = sans(22)
    draw.text((48, H - 44), left, font=f, fill=MUTED)
    w = draw.textlength(right, font=f)
    draw.text((W - 48 - w, H - 44), right, font=f, fill=FAINT)


def header(draw, title, right="FLASHEXIT"):
    f = sans(26, bold=True)
    draw.text((48, 30), title, font=f, fill=TEXT)
    f2 = sans(22, bold=True)
    w = draw.textlength(right, font=f2)
    draw.text((W - 48 - w, 34), right, font=f2, fill=FAINT)
    draw.line([(48, 78), (W - 48, 78)], fill=BORDER, width=2)


def short(h, n=10):
    return h[:n] + "..." + h[-4:]


def title_card():
    img = canvas()
    draw = ImageDraw.Draw(img)
    badge(draw, 48, 48, "REACTIVE OMNI BUILDATHON  ·  TRACK 1: EVERY SECOND COUNTS",
          ACCENT, (16, 36, 64), sans(24, bold=True))
    draw.text((48, 150), "FlashExit", font=sans(150, bold=True), fill=TEXT)
    draw.text((48, 320), "A cross-chain stop-loss that fires itself, in seconds.",
              font=sans(44), fill=ACCENT)
    for i, ln in enumerate(wrap(draw, "A reactive contract watches the price on Base Sepolia and sells on Unichain Sepolia the moment your trigger is crossed. No keeper. No polling.", sans(30), 1500)):
        draw.text((48, 430 + i * 46), ln, font=sans(30), fill=MUTED)
    bx, by, bw, bh, gap = 48, 700, 520, 150, 96
    for j, (tag, l1, l2, fill, ofill, tcol) in enumerate([
        ("BASE SEPOLIA", "Price moves here", "Uniswap v4 pool", BG2, BORDER, FAINT),
        ("LASNA", "Reactive contract", "Watches. Reacts.", (14, 48, 28), (40, 120, 60), GREEN_BRIGHT),
        ("UNICHAIN SEPOLIA", "Exit executes here", "Proceeds to you", BG2, BORDER, FAINT),
    ]):
        x = bx + j * (bw + gap)
        rounded(draw, [x, by, x + bw, by + bh], 16, fill=fill, outline=ofill, width=2)
        draw.text((x + 28, by + 28), tag, font=sans(22, bold=True), fill=tcol)
        draw.text((x + 28, by + 66), l1, font=sans(28, bold=True), fill=TEXT)
        draw.text((x + 28, by + 104), l2, font=sans(28), fill=TEXT)
        if j < 2:
            draw.text((x + bw + 24, by + 48), "->", font=sans(48, bold=True), fill=ACCENT)
    footer(draw)
    return img


def problem_slide():
    img = canvas()
    draw = ImageDraw.Draw(img)
    header(draw, "THE PROBLEM  ·  YOUR TOKENS AND THE PRICE LIVE ON DIFFERENT CHAINS")
    lx, lw = 48, 880
    rounded(draw, [lx, 120, lx + lw, 520], 14, fill=TERM_BG, outline=BORDER, width=2)
    draw.text((lx + 28, 150), "Where your tokens live", font=sans(26, bold=True), fill=MUTED)
    draw.text((lx + 28, 230), "Unichain Sepolia.", font=mono(32, bold=True), fill=TEXT)
    draw.text((lx + 28, 278), "100 FLASH, sitting in", font=mono(32, bold=True), fill=TEXT)
    draw.text((lx + 28, 326), "an executor contract.", font=mono(32, bold=True), fill=TEXT)
    draw.text((lx + 28, 460), "Ready to sell. Waiting for a signal.", font=sans(24), fill=MUTED)
    rx = 992
    rounded(draw, [rx, 120, rx + lw, 520], 14, fill=TERM_BG, outline=BORDER, width=2)
    draw.text((rx + 28, 150), "Where the price moves", font=sans(26, bold=True), fill=MUTED)
    draw.text((rx + 28, 230), "Base Sepolia.", font=mono(32, bold=True), fill=TEXT)
    draw.text((rx + 28, 278), "The liquid pool.", font=mono(32, bold=True), fill=TEXT)
    draw.text((rx + 28, 326), "The price that matters.", font=mono(32, bold=True), fill=TEXT)
    draw.text((rx + 28, 460), "A swap here should trigger a sale there.", font=sans(24), fill=MUTED)
    draw.text((48, 600), "Keepers poll. Humans sleep.", font=sans(40, bold=True), fill=TEXT)
    draw.text((48, 660), "By the time anyone reacts, the exit price is gone.", font=sans(40, bold=True), fill=RED)
    draw.text((48, 780), "A stop-loss is only as fast as whoever watches the market.", font=sans(32), fill=MUTED)
    footer(draw)
    return img


def idea_slide():
    img = canvas()
    draw = ImageDraw.Draw(img)
    header(draw, "HOW IT WORKS  ·  WATCH, REACT, EXIT")
    boxes = [
        ("1. WATCH", "Lasna watches Base",
         "FlashExitReactive subscribes to Uniswap v4 Swap events of the Base Sepolia pool. The network delivers each event to react(), no polling.",
         (16, 36, 64)),
        ("2. REACT", "Trigger crossed, callback fired",
         "When the pool price crosses an order's trigger, the order is marked Triggered and a callback is requested to Unichain Sepolia.",
         (16, 36, 64)),
        ("3. EXIT", "Swap runs, proceeds to you",
         "FlashExitExecutor sells the pre-deposited tokens in the Unichain pool and sends the output straight to the order owner.",
         (14, 48, 28)),
    ]
    bx, by, bw, bh, gap = 48, 120, 576, 420, 24
    for i, (tag, title, body, fill) in enumerate(boxes):
        x = bx + i * (bw + gap)
        rounded(draw, [x, by, x + bw, by + bh], 16, fill=fill, outline=BORDER, width=2)
        draw.text((x + 28, by + 28), tag, font=sans(22, bold=True), fill=ACCENT)
        draw.text((x + 28, by + 66), title, font=sans(30, bold=True), fill=TEXT)
        for j, ln in enumerate(wrap(draw, body, sans(26), bw - 56)):
            draw.text((x + 28, by + 130 + j * 40), ln, font=sans(26), fill=MUTED)
        if i < 2:
            draw.text((x + bw + 2, by + 240), ">", font=sans(30, bold=True), fill=FAINT)
    draw.text((48, 620), "No keeper. No polling. No wallet online.", font=sans(36, bold=True), fill=TEXT)
    draw.text((48, 680), "The Reactive Network itself is the watcher.", font=sans(32), fill=MUTED)
    draw.text((48, 740), "Orders: stop-loss and take-profit, each with its own trigger, minOut and deadline.",
              font=sans(26), fill=FAINT)
    footer(draw)
    return img


def order_slide():
    img = canvas()
    draw = ImageDraw.Draw(img)
    header(draw, "THE ORDER  ·  STOP-LOSS, ORDER 2 (LIVE RUN)")
    rounded(draw, [48, 120, 1872, 560], 14, fill=TERM_BG, outline=BORDER, width=2)
    rows = [
        ("Sell", "100 FLASH", TEXT),
        ("Trigger", "price falls 8% (sqrtPriceX96 9.90e28)", TEXT),
        ("Min output", "0 mUSD (demo; a real order sets a floor)", MUTED),
        ("Deadline", "7 days, then the order expires on its own", MUTED),
        ("Deposit", "100 FLASH pre-deposited in the executor", GREEN_BRIGHT),
    ]
    yy = 160
    for label, val, col in rows:
        draw.text((88, yy), label, font=sans(28, bold=True), fill=FAINT)
        draw.text((400, yy), val, font=sans(30, bold=True), fill=col)
        yy += 74
    draw.text((48, 640), "The exit needs no approval at trigger time.", font=sans(36, bold=True), fill=TEXT)
    draw.text((48, 700), "The tokens are already there. The trigger is all that is missing.",
              font=sans(32), fill=MUTED)
    draw.text((48, 800), "Order created on Lasna, block 9086790.",
              font=mono(26), fill=FAINT)
    footer(draw)
    return img


def trigger_slide():
    img = canvas()
    draw = ImageDraw.Draw(img)
    header(draw, "THE TRIGGER  ·  BASE SEPOLIA, LIVE")
    rounded(draw, [48, 120, 1872, 560], 14, fill=TERM_BG, outline=BORDER, width=2)
    draw.text((88, 160), "A 10,000 FLASH sell hits the Base pool.", font=sans(32, bold=True), fill=TEXT)
    draw.text((88, 240), "Price falls 15%, far past the trigger.", font=sans(32, bold=True), fill=RED)
    draw.text((88, 330), "sqrtPriceX96   9.50e28  ->  1.03e29", font=mono(34, bold=True), fill=TEXT)
    draw.text((88, 390), "trigger        9.90e28  crossed", font=mono(34, bold=True), fill=YELLOW)
    draw.text((88, 470), "tx " + short("0xa0fdf25093db423dec5e86e2af1c2177b5500e8431084bc21248cafd3676874e"),
              font=mono(26), fill=MUTED)
    draw.text((48, 640), "The Swap event is now on its way to Lasna.", font=sans(36, bold=True), fill=TEXT)
    draw.text((48, 700), "Base Sepolia block 62741460.", font=sans(30), fill=MUTED)
    footer(draw)
    return img


def reaction_slide():
    img = canvas()
    draw = ImageDraw.Draw(img)
    header(draw, "THE REACTION  ·  LASNA, SAME SECOND")
    rounded(draw, [48, 120, 1872, 560], 14, fill=(14, 48, 28), outline=(40, 120, 60), width=2)
    draw.text((88, 160), "OrderTriggered", font=mono(40, bold=True), fill=GREEN_BRIGHT)
    draw.text((88, 240), "order 2  ·  Lasna block 9086812", font=sans(32, bold=True), fill=TEXT)
    draw.text((88, 320), "react() sees the Swap event, marks the order", font=sans(30), fill=MUTED)
    draw.text((88, 368), "Triggered, and requests the callback.", font=sans(30), fill=MUTED)
    draw.text((88, 460), "tx " + short("0x6f65176d3bbf347cc4f751f1179bf9a8d8a1c1d6902c705db5d3c1d32828ce8a"),
              font=mono(26), fill=MUTED)
    draw.text((48, 640), "Trigger to reaction: 0 seconds.", font=sans(40, bold=True), fill=GREEN_BRIGHT)
    draw.text((48, 700), "Block timestamps: trigger and reaction share the same second.",
              font=sans(30), fill=MUTED)
    footer(draw)
    return img


def exit_slide():
    img = canvas()
    draw = ImageDraw.Draw(img)
    header(draw, "THE EXIT  ·  UNICHAIN SEPOLIA, MEASURED LIVE")
    rounded(draw, [48, 120, 1872, 470], 14, fill=(14, 48, 28), outline=(40, 120, 60), width=2)
    draw.text((88, 160), "ExitExecuted", font=mono(40, bold=True), fill=GREEN_BRIGHT)
    draw.text((88, 240), "100 FLASH  ->  99.60 mUSD, straight to the user", font=sans(32, bold=True), fill=TEXT)
    draw.text((88, 320), "tx " + short("0xd31c19aa349548cd6b4812bff208e18131b948681bd3ca9ea04b39f85387fdcb") +
              "  ·  block 68617735", font=mono(26), fill=MUTED)
    draw.text((88, 390), "Trigger to exit: 3 seconds.", font=sans(34, bold=True), fill=GREEN_BRIGHT)
    # latency table
    draw.text((48, 540), "Measured latency, both live runs:", font=sans(30, bold=True), fill=TEXT)
    rows = [
        ("Stop-loss, order 2", "3 s"),
        ("Take-profit, order 3", "2 s"),
    ]
    yy = 600
    for label, val in rows:
        draw.text((88, yy), label, font=sans(30), fill=MUTED)
        w = draw.textlength(val, font=sans(30, bold=True))
        draw.text((1872 - 40 - w, yy), val, font=sans(30, bold=True), fill=GREEN_BRIGHT)
        yy += 56
    draw.text((48, 740), "Block timestamps, via script/measure-latency.py.",
              font=sans(24), fill=FAINT)
    footer(draw)
    return img


def safeguards_slide():
    img = canvas()
    draw = ImageDraw.Draw(img)
    header(draw, "THREE SAFEGUARDS")
    boxes = [
        ("1. FIRES ONCE", "The order is marked Triggered before the callback is requested. A volatile pool cannot double-fire it."),
        ("2. SLIPPAGE GUARD", "If the swap output falls below minOut, the callback reverts and the deposit stays untouched."),
        ("3. EXPIRY", "Expired orders are skipped, never executed. A stale trigger cannot sell your tokens a week later."),
    ]
    bx, by, bw, bh, gap = 48, 140, 576, 380, 24
    for i, (tag, body) in enumerate(boxes):
        x = bx + i * (bw + gap)
        rounded(draw, [x, by, x + bw, by + bh], 16, fill=BG2, outline=BORDER, width=2)
        draw.text((x + 28, by + 28), tag, font=sans(24, bold=True), fill=ACCENT)
        for j, ln in enumerate(wrap(draw, body, sans(28), bw - 56)):
            draw.text((x + 28, by + 90 + j * 44), ln, font=sans(28), fill=TEXT)
    draw.text((48, 620), "The exit is automatic. The rules are yours.", font=sans(36, bold=True), fill=TEXT)
    draw.text((48, 680), "Trigger, floor, deadline: set once, then walk away.", font=sans(32), fill=MUTED)
    footer(draw)
    return img


def bothways_slide():
    img = canvas()
    draw = ImageDraw.Draw(img)
    header(draw, "IT WORKS BOTH WAYS  ·  TAKE-PROFIT, ORDER 3")
    rounded(draw, [48, 120, 1872, 560], 14, fill=TERM_BG, outline=BORDER, width=2)
    draw.text((88, 160), "A take-profit order fires when the price rises.", font=sans(32, bold=True), fill=TEXT)
    draw.text((88, 240), "Same flow, same speed.", font=sans(32, bold=True), fill=GREEN_BRIGHT)
    draw.text((88, 330), "100 FLASH  ->  99.40 mUSD in 2 seconds", font=mono(34, bold=True), fill=TEXT)
    draw.text((88, 410), "trigger tx " + short("0xd98a58eef3b44cce6165029a760d2d1647c4f2ca06a12027bb00da4ad02925d6"),
              font=mono(26), fill=MUTED)
    draw.text((88, 460), "exit tx    " + short("0xd798e10c01006a942f3bde79fbce5d8d9eded32c1f34a2d7a3415fb47bc52682"),
              font=mono(26), fill=MUTED)
    draw.text((48, 640), "One contract watches both directions.", font=sans(36, bold=True), fill=TEXT)
    draw.text((48, 700), "Stop-loss below, take-profit above, same registry.", font=sans(30), fill=MUTED)
    footer(draw)
    return img


def closing_card():
    img = canvas()
    draw = ImageDraw.Draw(img)
    draw.text((48, 120), "FlashExit", font=sans(84, bold=True), fill=TEXT)
    draw.text((48, 220), "Set the trigger, walk away, and let the", font=sans(40), fill=ACCENT)
    draw.text((48, 275), "network watch the market for you.", font=sans(40), fill=ACCENT)
    rounded(draw, [48, 400, 1872, 640], 14, fill=BG2, outline=BORDER, width=2)
    draw.text((88, 430), "FlashExitReactive (Lasna)", font=sans(26), fill=MUTED)
    draw.text((88, 470), "0x8626fd3711de3bcAebd891De1321c08eD6774bF3", font=mono(30, bold=True), fill=TEXT)
    draw.text((88, 530), "FlashExitExecutor (Unichain Sepolia)", font=sans(26), fill=MUTED)
    draw.text((88, 570), "0xA316777667B4b8c6f65C8D123e64F0cdbB9401E7", font=mono(30, bold=True), fill=TEXT)
    draw.text((48, 700), "Reactive Omni Buildathon  ·  Track 1: Every Second Counts  ·  by cezo484",
              font=sans(26), fill=MUTED)
    draw.text((48, 760), "Testnet only. Thanks for watching.", font=sans(30, bold=True), fill=TEXT)
    footer(draw)
    return img


if __name__ == "__main__":
    import sys
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    for name, fn in [("title", title_card), ("problem", problem_slide),
                     ("idea", idea_slide), ("order", order_slide),
                     ("trigger", trigger_slide), ("reaction", reaction_slide),
                     ("exit", exit_slide), ("safeguards", safeguards_slide),
                     ("bothways", bothways_slide), ("closing", closing_card)]:
        fn().save(os.path.join(out, f"{name}.png"))
        print("wrote", name + ".png")
