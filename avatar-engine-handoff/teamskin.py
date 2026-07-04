import re, colorsys, cairosvg

data = open('/mnt/user-data/uploads/sim1.svg').read()

def region_of(h, s, v):
    if s < 0.15 or v < 0.22: return None          # line art, visor, background
    if h >= 0.97 or h < 0.028: return 'chest'      # red
    if h < 0.088: return 'sleeves'                 # orange
    if h < 0.155: return 'hstripe'                 # yellow (helmet stripe)
    if h < 0.243: return 'accents'                 # lime (collar/belt)
    if h < 0.400: return 'legs'                    # green
    if h < 0.548: return 'helmet'                  # teal/cyan
    if h < 0.660: return 'boots'                   # blue
    if h < 0.830: return 'stripes'                 # purple (side stripes)
    return 'gloves'                                # magenta

def apply(hexcol, palette):
    r,g,b = int(hexcol[1:3],16)/255, int(hexcol[3:5],16)/255, int(hexcol[5:7],16)/255
    h,s,v = colorsys.rgb_to_hsv(r,g,b)
    reg = region_of(h,s,v)
    if reg is None or reg not in palette: return hexcol
    mode = palette[reg]
    if mode[0] == 'hue':                 # ('hue', target_h, s_scale)
        h = mode[1]; s = min(1.0, s*mode[2])
    elif mode[0] == 'neutral':           # ('neutral', s_fixed, v_a, v_b) -> v' = a + b*v
        s = mode[1]; v = min(1.0, mode[2] + mode[3]*v)
    r,g,b = colorsys.hsv_to_rgb(h,s,v)
    return '#%02x%02x%02x' % (round(r*255),round(g*255),round(b*255))

teams = {
 'ferrari': {   # rosso corsa, white accents, yellow helmet stripe stays
   'chest':('hue',0.995,1.0), 'sleeves':('hue',0.995,1.0), 'legs':('hue',0.995,1.0),
   'gloves':('hue',0.995,1.0), 'helmet':('hue',0.995,1.0),
   'accents':('neutral',0.03,0.55,0.45), 'stripes':('neutral',0.03,0.55,0.45),
   'boots':('neutral',0.08,0.02,0.40),
 },
 'mercedes': {  # silver, black legs/gloves, petronas teal details
   'chest':('neutral',0.05,0.42,0.50), 'sleeves':('neutral',0.05,0.42,0.50),
   'helmet':('neutral',0.05,0.42,0.50),
   'legs':('neutral',0.06,0.03,0.38), 'gloves':('neutral',0.06,0.03,0.38),
   'boots':('neutral',0.06,0.02,0.35),
   'accents':('hue',0.49,0.95), 'stripes':('hue',0.49,0.95), 'hstripe':('hue',0.49,0.95),
 },
 'mclaren': {   # papaya top, anthracite legs, papaya leg stripes
   'chest':('hue',0.058,1.0), 'sleeves':('hue',0.058,1.0), 'helmet':('hue',0.058,1.0),
   'legs':('neutral',0.07,0.06,0.42), 'gloves':('neutral',0.07,0.03,0.38),
   'boots':('neutral',0.07,0.02,0.35),
   'accents':('neutral',0.07,0.06,0.42), 'stripes':('hue',0.058,1.0),
   'hstripe':('neutral',0.08,0.05,0.40),
 },
}

for name, pal in teams.items():
    out = re.sub(r'#[0-9a-fA-F]{6}', lambda m: apply(m.group(0), pal), data)
    open(f'{name}.svg','w').write(out)
    cairosvg.svg2png(bytestring=out.encode(), write_to=f'{name}.png', output_width=340)
print('done')
