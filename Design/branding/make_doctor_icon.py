import random, math
from PIL import Image, ImageDraw, ImageFilter, ImageChops
# Run from Design/branding/. Makes the LifeTrack Clinic icon from the patient icon.
SRC='patient-icon-foreground-432.png'
im=Image.open(SRC).convert('RGB'); px=im.load()
# 1. Fit a plane per channel to the card surface around the heart, then repaint the heart area.
X0,X1,Y0,Y1=211,331,168,293
def in_box(x,y): return X0<=x<=X1 and Y0<=y<=Y1
samples=[]
for y in range(156,306):
    for x in range(204,334):
        if in_box(x,y): continue
        if x>296 and 210<y<268: continue   # lime glow
        r,g,b=px[x,y]
        if (r+g+b)/3<150: continue           # not card surface
        samples.append((x,y,(r,g,b)))
def solve(c):
    S=[[0]*3 for _ in range(3)]; v=[0]*3
    for x,y,col in samples:
        f=(x,y,1); t=col[c]
        for i in range(3):
            v[i]+=f[i]*t
            for j in range(3): S[i][j]+=f[i]*f[j]
    # Gaussian elimination
    A=[S[i]+[v[i]] for i in range(3)]
    for i in range(3):
        p=max(range(i,3),key=lambda r:abs(A[r][i])); A[i],A[p]=A[p],A[i]
        for r in range(3):
            if r!=i:
                k=A[r][i]/A[i][i]; A[r]=[a-k*b for a,b in zip(A[r],A[i])]
    return [A[i][3]/A[i][i] for i in range(3)]
coef=[solve(c) for c in range(3)]
random.seed(7)
# soft-edged mask so the patch blends into the card
mask=Image.new('L',im.size,0); ImageDraw.Draw(mask).rounded_rectangle((X0,Y0,X1,Y1),radius=10,fill=255)
mask=mask.filter(ImageFilter.GaussianBlur(2))
fill=Image.new('RGB',im.size); fp=fill.load()
for y in range(Y0-6,Y1+7):
    for x in range(X0-6,X1+7):
        n=random.uniform(-1.6,1.6)
        fp[x,y]=tuple(max(0,min(255,int(round(a*x+b*y+c+n)))) for a,b,c in coef)
im=Image.composite(fill,im,mask)

# 2. Draw ℞ + pulse at 4x, slightly tilted to sit with the card.
S=4; W=im.size[0]*S
ink=Image.new('L',(W,W),0); d=ImageDraw.Draw(ink)
def P(*pts): return [(x*S,y*S) for x,y in pts]
sw=15*S
stem_x=236; top=176; bowl_bot=224; bottom=282
# stem
d.line(P((stem_x,top),(stem_x,bottom)),fill=255,width=sw,joint="curve")
# bowl: top bar, arc, bottom bar
r=(bowl_bot-top)/2; cx=266
d.line(P((stem_x,top),(cx,top)),fill=255,width=sw)
d.line(P((stem_x,bowl_bot),(cx,bowl_bot)),fill=255,width=sw)
h=sw/2/S; d.arc([ (cx-r-h)*S,(top-h)*S,(cx+r+h)*S,(bowl_bot+h)*S ],start=-90,end=90,fill=255,width=sw)
# leg
d.line(P((258,bowl_bot),(296,284)),fill=255,width=sw)
for (x,y) in [(stem_x,top),(stem_x,bottom),(296,284)]:
    d.ellipse([(x*S-sw/2),(y*S-sw/2),(x*S+sw/2),(y*S+sw/2)],fill=255)
# pulse line = the crossing stroke of ℞, ending at the lime dot
pw=7*S; py=252
pulse=P((264,py),(286,py),(291,py-12),(298,py+12),(303,py),(316,py))
d.line(pulse,fill=255,width=pw,joint="curve")
for (x,y) in [pulse[0]]:
    d.ellipse([x-pw/2,y-pw/2,x+pw/2,y+pw/2],fill=255)
ink=ink.rotate(-3,center=(270*S,232*S),resample=Image.BICUBIC).resize(im.size,Image.LANCZOS)

# soft drop shadow, then glossy black ink (top lighter, like the heart)
shadow=ink.filter(ImageFilter.GaussianBlur(3)); shadow=ImageChops.offset(shadow,1,3)
im=Image.composite(Image.new('RGB',im.size,(70,72,68)),im,shadow.point(lambda v:int(v*0.45)))
grad=Image.new('RGB',im.size); gp=grad.load()
for y in range(im.size[1]):
    t=max(0,min(1,(y-170)/120)); col=int(52-30*t)
    for x in range(160,360): gp[x,y]=(col,col,col-2)
im=Image.composite(grad,im,ink)

# 3. Lime "now" dot with glow at the end of the pulse (where the original sat).
gx,gy=323,251
glow=Image.new('RGB',im.size,(0,0,0)); g=ImageDraw.Draw(glow)
for rad in range(22,0,-1):
    a=(1-rad/22)**2
    g.ellipse((gx-rad,gy-rad,gx+rad,gy+rad),fill=(int(200*a),int(240*a),int(40*a)))
glow=glow.filter(ImageFilter.GaussianBlur(2))
im=ImageChops.screen(im,glow)
core=Image.new('L',im.size,0); ImageDraw.Draw(core).ellipse((gx-6,gy-6,gx+6,gy+6),fill=255)
core=core.filter(ImageFilter.GaussianBlur(1))
im=Image.composite(Image.new('RGB',im.size,(240,255,200)),im,core)
ring=Image.new('L',im.size,0); ImageDraw.Draw(ring).ellipse((gx-7,gy-7,gx+7,gy+7),outline=255,width=2)
im=Image.composite(Image.new('RGB',im.size,(214,243,90)),im,ring.filter(ImageFilter.GaussianBlur(.8)))
im.save('doctor-icon-foreground-432.png')
