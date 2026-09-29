"""Local procedural icon artwork. Run with Python, Pillow and NumPy."""
from pathlib import Path
import json
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

ROOT = Path(__file__).resolve().parent
S = 1536
K = S / 1024
rng = np.random.default_rng(20260928)
Y, X = np.mgrid[0:S, 0:S].astype(np.float32) / K
NOISE = rng.normal(0, 1, (S, S)).astype(np.float32)


def mask():
    return Image.new('L', (S, S))


def path(commands):
    points = []
    current = (0, 0)
    for cmd in commands:
        if cmd[0] == 'M' or cmd[0] == 'L':
            current = cmd[1:]
            points.append(current)
        elif cmd[0] == 'C':
            p0 = current
            p1, p2, p3 = cmd[1:3], cmd[3:5], cmd[5:7]
            for t in np.linspace(0, 1, 45)[1:]:
                points.append(tuple((1-t)**3*p0[i]+3*(1-t)**2*t*p1[i]+3*(1-t)*t*t*p2[i]+t**3*p3[i] for i in (0, 1)))
            current = p3
    return [(round(x*K), round(y*K)) for x, y in points]


def shape(commands):
    m = mask()
    ImageDraw.Draw(m).polygon(path(commands), fill=255)
    return m


def stroke(commands, width):
    m = mask()
    pts = path(commands)
    d = ImageDraw.Draw(m)
    d.line(pts, fill=255, width=round(width*K), joint='curve')
    r = width*K/2
    for x, y in (pts[0], pts[-1]):
        d.ellipse((x-r, y-r, x+r, y+r), fill=255)
    return m


def rounded(box, radius):
    m = mask()
    ImageDraw.Draw(m).rounded_rectangle(tuple(v*K for v in box), radius*K, fill=255)
    return m


def shift(m, dx, dy):
    out = mask()
    out.paste(m, (round(dx*K), round(dy*K)))
    return out


def solid(m, color, opacity=1):
    im = Image.new('RGBA', (S, S), color)
    im.putalpha(m.point(lambda v: round(v*opacity)))
    return im


def paint(fg, m, color, material='flat', depth=12, shadow=True):
    if shadow:
        sm = shift(m, 3, depth+9).filter(ImageFilter.GaussianBlur(11*K))
        fg.alpha_composite(solid(sm, '#1b1520', .20))
    rgb = np.array(ImageColor(color), dtype=np.float32)
    if depth:
        fg.alpha_composite(solid(shift(m, 0, depth), tuple((rgb*.62).astype(int))+(255,)))
    bevel = 0 if material == 'flat' else 6
    b = np.asarray(m.filter(ImageFilter.GaussianBlur(max(1, bevel)*K)), dtype=np.float32)/255
    gy, gx = np.gradient(b)
    light = (-gx-gy)*40
    v = np.zeros((S, S), dtype=np.float32)
    v += (500-Y)*.035
    if material != 'flat':
        v += light*42
    if material in ('clay', 'leather', 'paper', 'ink', 'thread'):
        v += NOISE * {'clay':2.0, 'leather':3.5, 'paper':1.4, 'ink':3.5, 'thread':2}[material]
    if material in ('enamel', 'glass', 'ceramic'):
        v += 45*np.exp(-((X+Y-670)/100)**2) + 15*np.exp(-((X-620)/80)**2)
    if material == 'wood':
        v += 7*np.sin(X*.16+4*np.sin(Y*.009))+3*np.sin(X*.65+np.sin(Y*.018))
    if material == 'thread':
        v += 5*np.sin((X+Y)*1.1)+3*np.sin((X-Y)*1.3)
    pixels = np.clip(rgb[None,None,:] + v[:,:,None], 0, 255).astype(np.uint8)
    im = Image.fromarray(pixels, 'RGB').convert('RGBA')
    im.putalpha(m)
    fg.alpha_composite(im)


def ImageColor(c):
    c = c.lstrip('#')
    return tuple(int(c[i:i+2], 16) for i in (0, 2, 4))


LEFT = [('M',512,450),('C',439,392,349,376,274,406),('L',274,662),('C',357,633,437,665,512,714)]
RIGHT = [('M',512,450),('C',585,392,675,376,750,406),('L',750,662),('C',667,633,587,665,512,714)]
ARCH = [('M',251,528),('L',251,436),('C',251,125,773,125,773,436),('L',773,528)]

STYLES = [
 ('01_geometric','几何','#f3eee8','#8056df','#ff8a32','flat'),
 ('02_skeuomorphic','拟物','#eee5d6','#493e35','#d98942','leather'),
 ('03_enamel','珐琅','#e9eeee','#166879','#35b9af','enamel'),
 ('04_ink','水墨','#f2eee3','#292f30','#697775','ink'),
 ('05_clay','黏土','#f5e9df','#ef715a','#ffc44a','clay'),
 ('06_frosted_glass','磨砂玻璃','#e9eefb','#8b8de7','#60c9d9','glass'),
 ('07_origami','折纸','#f4ece1','#df6650','#efa648','paper'),
 ('08_wood','木雕','#eae3d7','#75503a','#c89b65','wood'),
 ('09_embroidery','刺绣','#e9e8e1','#6c6993','#dd8c55','thread'),
 ('10_retro','复古搪瓷','#f3e4cc','#376c64','#e89a4d','ceramic'),
]


def background(color, material):
    rgb = np.array(ImageColor(color), dtype=np.float32)
    rad = ((X-430)**2+(Y-340)**2)/1024**2
    light = 6-12*rad
    if material in ('ink', 'paper', 'thread', 'wood', 'leather'):
        light += NOISE*.65
    if material == 'thread':
        light += .8*np.sin(X*1.8)+.8*np.sin(Y*1.8)
    return Image.fromarray(np.clip(rgb[None,None,:]+light[:,:,None],0,255).astype('uint8')).convert('RGBA')


def make(style):
    folder, title, bgc, primary, accent, material = style
    fg = Image.new('RGBA',(S,S))
    flat = material in ('flat','ink','paper')
    depth = 0 if material == 'ink' else 7 if flat else 15
    arch = stroke(ARCH, 53 if material!='ink' else 30)
    left, right = shape(LEFT), shape(RIGHT)
    if material == 'enamel':
        # Gold cloisonne boundaries surround independently filled enamel cells.
        for m in (arch, left, right):
            paint(fg, m.filter(ImageFilter.MaxFilter(25)), '#c79b50','enamel',8)
    paint(fg,arch,primary,material,depth)
    for box in ((213,450,285,583),(739,450,811,583)):
        paint(fg,rounded(box,30),primary,material,depth)
    if material in ('leather','ceramic'):
        for box in ((226,468,269,563),(755,468,798,563)):
            paint(fg,rounded(box,19),'#e7bc77' if material=='ceramic' else '#272c30',material,4,False)
    # Book cover and paper block sit above the headphone cups.
    book = ImageChops.lighter(left,right)
    paint(fg,shift(book,0,15),primary,material,depth)
    if material=='leather':
        paint(fg,left,'#fff0ce','paper',6)
        paint(fg,right,'#f7e1b5','paper',6)
    else:
        paint(fg,left,accent,material,depth)
        paint(fg,right,primary if material in ('flat','paper') else accent,material,depth)
    # Curved printed / embossed page lines.
    linecolor = '#aa8355' if material=='leather' else '#f8e8c3' if material in ('enamel','wood','ceramic') else '#ffffff'
    for side in (0,1):
        for yy in (490,532,574):
            if side==0:
                curve=[('M',318,yy),('C',370,yy-6,420,yy+10,463,yy+35)]
            else:
                curve=[('M',561,yy+35),('C',604,yy+10,654,yy-6,706,yy)]
            if material == 'flat' and yy!=532:
                continue
            line=stroke(curve,8 if material!='ink' else 5)
            fg.alpha_composite(solid(line,linecolor,.55 if material not in ('ink','leather') else .55))
    seam=stroke([('M',512,464),('L',512,688)],5)
    fg.alpha_composite(solid(seam,'#352b2a',.20))
    # A small amber bookmark reinforces the reading identity.
    if material not in ('ink','paper'):
        ribbon=shape([('M',651,398),('L',678,394),('L',678,478),('L',664,465),('L',651,480)])
        paint(fg,ribbon,'#db7254' if material in ('wood','leather','ceramic') else '#ffe7a8',material,3,False)
    # Sound floating in the negative space within the headphone arch.
    for x,h in ((465,29),(512,58),(559,39)):
        wave=rounded((x-10,325-h/2,x+10,325+h/2),10)
        paint(fg,wave,accent if material!='ink' else '#ad493a',material,3 if not flat else 0,False)
    if material=='paper':
        fold=shape([('M',274,406),('L',512,450),('L',313,627)])
        fg.alpha_composite(solid(fold,'#fff3db',.17))
        fold=shape([('M',512,450),('L',750,406),('L',706,635)])
        fg.alpha_composite(solid(fold,'#6c2741',.13))
    if material=='glass':
        for m in (left,right):
            edge=ImageChops.subtract(m,m.filter(ImageFilter.MinFilter(7)))
            fg.alpha_composite(solid(edge,'#ffffff',.65))
        glint=stroke([('M',316,425),('C',366,417,407,427,452,451)],5)
        fg.alpha_composite(solid(glint,'#ffffff',.65))
    if material=='thread':
        d=ImageDraw.Draw(fg)
        for cmds in (LEFT,RIGHT):
            pts=path(cmds)
            pts.append(pts[0])
            for i in range(len(pts)-1):
                x1,y1=pts[i];x2,y2=pts[i+1]
                dist=math.hypot(x2-x1,y2-y1)
                n=max(1,int(dist/(10*K)))
                for t in np.linspace(0,1,n,endpoint=False):
                    x=x1+(x2-x1)*t;y=y1+(y2-y1)*t
                    d.line((x-3*K,y-3*K,x+3*K,y+3*K),fill='#f7dabb',width=round(2*K))
    if material=='ink':
        a=np.asarray(fg.getchannel('A')).copy()
        dry=(np.sin(X*.6+Y*.12)+NOISE*1.2)>2.4
        a[dry]=(a[dry]*.4).astype('uint8')
        fg.putalpha(Image.fromarray(a))
        d=ImageDraw.Draw(fg)
        for _ in range(60):
            x,y=rng.uniform(220,800),rng.uniform(280,730)
            r=rng.uniform(.6,2.8)*K
            d.ellipse((x*K-r,y*K-r,x*K+r,y*K+r),fill=(41,45,42,70))
        stamp=rounded((694,710,746,762),4)
        fg.alpha_composite(solid(stamp,'#a84434',.90))
        for xx in (709,727):
            fg.alpha_composite(solid(stroke([('M',xx,722),('L',xx,750)],4),'#f2eee3'))
    bg=background(bgc,material)
    fg=fg.resize((1024,1024),Image.Resampling.LANCZOS)
    bg=bg.resize((1024,1024),Image.Resampling.LANCZOS)
    dest=ROOT/folder
    dest.mkdir(exist_ok=True)
    fg.save(dest/'app_icon_foreground.png',optimize=True)
    bg.save(dest/'app_icon_background.png',optimize=True)
    legacy=Image.alpha_composite(bg,fg)
    legacy.save(dest/'app_icon_legacy.png',optimize=True)
    (dest/'app_icon.json').write_text(json.dumps({'layered-image':{'background':'$media:app_icon_background','foreground':'$media:app_icon_foreground'}},indent=2)+'\n',encoding='utf-8')
    print(folder,flush=True)
    return legacy


def font(size):
    return ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',size)


def main():
    icons=[make(s) for s in STYLES]
    sheet=Image.new('RGB',(1800,990),'#f5f4f1')
    d=ImageDraw.Draw(sheet)
    d.text((52,28),'简听 · 十种材质图标',font=font(35),fill='#292d34')
    d.text((54,83),'书本 × 声音  /  1024 px  /  分层 PNG',font=font(18),fill='#7c8089')
    for i,(im,st) in enumerate(zip(icons,STYLES)):
        x=52+(i%5)*348;y=144+(i//5)*414
        thumb=im.resize((304,304),Image.Resampling.LANCZOS)
        sheet.paste(thumb,(x,y))
        d.text((x+2,y+319),f'{i+1:02d}  {st[1]}',font=font(23),fill='#343740')
    sheet.save(ROOT/'总览.png',optimize=True)
    # Verify deliverable dimensions, alpha, layer references and exact recomposition.
    for st in STYLES:
        p=ROOT/st[0]
        fg=Image.open(p/'app_icon_foreground.png');bg=Image.open(p/'app_icon_background.png')
        preview=Image.open(p/'app_icon_legacy.png')
        assert fg.size==bg.size==preview.size==(1024,1024)
        assert fg.mode==bg.mode==preview.mode=='RGBA'
        assert fg.getchannel('A').getextrema()==(0,255)
        assert bg.getchannel('A').getextrema()==(255,255)
        assert not ImageChops.difference(Image.alpha_composite(bg,fg),preview).getbbox()
    print('Validated 10 layered icon sets.',flush=True)


if __name__=='__main__':
    main()
