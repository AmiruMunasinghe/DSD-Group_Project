#!/usr/bin/env python3
"""Tiny RV32I assembler: python asm.py prog.s out.hex  (1024-word $readmemh file)"""
import sys, re

ABI = {'zero':0,'ra':1,'sp':2,'gp':3,'tp':4,'t0':5,'t1':6,'t2':7,'s0':8,'fp':8,'s1':9}
for i in range(8):  ABI[f'a{i}'] = 10 + i
for i in range(2, 12): ABI[f's{i}'] = 16 + i
for i in range(3, 7):  ABI[f't{i}'] = 25 + i
for i in range(32): ABI[f'x{i}'] = i

def reg(s):
    return ABI[s.strip()]

R = {'add':(0,0),'sub':(0,0x20),'sll':(1,0),'slt':(2,0),'sltu':(3,0),'xor':(4,0),
     'srl':(5,0),'sra':(5,0x20),'or':(6,0),'and':(7,0)}
I = {'addi':0,'slti':2,'sltiu':3,'xori':4,'ori':6,'andi':7}
SH = {'slli':(1,0),'srli':(5,0),'srai':(5,0x20)}
L = {'lb':0,'lh':1,'lw':2,'lbu':4,'lhu':5}
S = {'sb':0,'sh':1,'sw':2}
B = {'beq':0,'bne':1,'blt':4,'bge':5,'bltu':6,'bgeu':7}

def enc_r(f7,rs2,rs1,f3,rd,op): return (f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op
def enc_i(imm,rs1,f3,rd,op): return ((imm&0xfff)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op
def enc_s(imm,rs2,rs1,f3,op):
    return (((imm>>5)&0x7f)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((imm&0x1f)<<7)|op
def enc_b(imm,rs2,rs1,f3):
    return (((imm>>12)&1)<<31)|(((imm>>5)&0x3f)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|\
           (((imm>>1)&0xf)<<8)|(((imm>>11)&1)<<7)|0x63
def enc_u(imm,rd,op): return ((imm&0xfffff)<<12)|(rd<<7)|op
def enc_j(imm,rd):
    return (((imm>>20)&1)<<31)|(((imm>>1)&0x3ff)<<21)|(((imm>>11)&1)<<20)|\
           (((imm>>12)&0xff)<<12)|(rd<<7)|0x6f

def num(s): return int(s.strip(), 0)

def expand(lines):
    """pseudo-instruction expansion; returns list of (mnemonic, [args])"""
    out = []
    for mn, a in lines:
        if mn == 'nop': out.append(('addi', ['x0','x0','0']))
        elif mn == 'mv': out.append(('addi', [a[0], a[1], '0']))
        elif mn == 'j': out.append(('jal', ['x0', a[0]]))
        elif mn == 'ret': out.append(('jalr', ['x0','ra','0']))
        elif mn == 'li':
            v = num(a[1]) & 0xffffffff
            sv = v - (1<<32) if v & 0x80000000 else v
            if -2048 <= sv < 2048: out.append(('addi', [a[0],'x0',str(sv)]))
            else:
                lo = sv & 0xfff
                if lo & 0x800: lo -= 0x1000
                hi = ((sv - lo) >> 12) & 0xfffff
                out.append(('lui', [a[0], str(hi)]))
                out.append(('addi', [a[0], a[0], str(lo)]))
        else: out.append((mn, a))
    return out

def main():
    src, dst = sys.argv[1], sys.argv[2]
    items, labels = [], {}
    for raw in open(src):
        line = raw.split('#')[0].strip()
        while ':' in line:
            lab, line = line.split(':', 1)
            labels[lab.strip()] = None
            labels[lab.strip()] = ('pending', len(items))
            line = line.strip()
        if not line: continue
        mn, _, rest = line.partition(' ')
        items.append((mn.lower(), [x.strip() for x in rest.split(',')] if rest.strip() else []))
    # labels recorded against pre-expansion index -> need post-expansion index
    pre = items
    post, idx_map = [], []
    for it in pre:
        idx_map.append(len(post)); post.extend(expand([it]))
    idx_map.append(len(post))
    lab = {k: idx_map[v[1]]*4 for k, v in labels.items()}

    def val(s, pc):
        s = s.strip()
        if s in lab: return lab[s] - pc
        return num(s)

    words = []
    for i, (mn, a) in enumerate(post):
        pc = i*4
        if mn in R:
            f3, f7 = R[mn]; w = enc_r(f7, reg(a[2]), reg(a[1]), f3, reg(a[0]), 0x33)
        elif mn in I: w = enc_i(num(a[2]), reg(a[1]), I[mn], reg(a[0]), 0x13)
        elif mn in SH:
            f3, f7 = SH[mn]; w = enc_i((f7<<5)|num(a[2]), reg(a[1]), f3, reg(a[0]), 0x13)
        elif mn in L or mn in S:
            m = re.match(r'(-?\w+)\((\w+)\)', a[1].replace(' ', ''))
            off, base = num(m.group(1)), reg(m.group(2))
            w = enc_i(off, base, L[mn], reg(a[0]), 0x03) if mn in L else \
                enc_s(off, reg(a[0]), base, S[mn], 0x23)
        elif mn in B: w = enc_b(val(a[2], pc), reg(a[1]), reg(a[0]), B[mn])
        elif mn == 'jal': w = enc_j(val(a[1], pc), reg(a[0]))
        elif mn == 'jalr': w = enc_i(num(a[2]), reg(a[1]), 0, reg(a[0]), 0x67)
        elif mn == 'lui': w = enc_u(num(a[1]), reg(a[0]), 0x37)
        elif mn == 'auipc': w = enc_u(num(a[1]), reg(a[0]), 0x17)
        else: sys.exit(f'unknown instruction: {mn}')
        words.append(w & 0xffffffff)
    words += [0x13] * (1024 - len(words))
    with open(dst, 'w') as f:
        for w in words: f.write(f'{w:08x}\n')
    print(f'{len(post)} instructions -> {dst}')

main()
