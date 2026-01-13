
vector_mul.elf:     file format elf32-littleriscv


Disassembly of section .text:

00000000 <_start>:
   0:	00040137          	lui	sp,0x40
   4:	090000ef          	jal	94 <main>
   8:	00050093          	mv	ra,a0
   c:	00000013          	nop
  10:	00000013          	nop
  14:	00000013          	nop
  18:	00000013          	nop
  1c:	00000013          	nop
  20:	00000073          	ecall

00000024 <loop>:
  24:	0000006f          	j	24 <loop>

00000028 <multiply>:
  28:	00050793          	mv	a5,a0
  2c:	04054263          	bltz	a0,70 <multiply+0x48>
  30:	0205ca63          	bltz	a1,64 <multiply+0x3c>
  34:	00000693          	li	a3,0
  38:	04058463          	beqz	a1,80 <multiply+0x58>
  3c:	00000513          	li	a0,0
  40:	0015f713          	andi	a4,a1,1
  44:	4015d593          	srai	a1,a1,0x1
  48:	00070463          	beqz	a4,50 <multiply+0x28>
  4c:	00f50533          	add	a0,a0,a5
  50:	00179793          	slli	a5,a5,0x1
  54:	fe0596e3          	bnez	a1,40 <multiply+0x18>
  58:	00068463          	beqz	a3,60 <multiply+0x38>
  5c:	40a00533          	neg	a0,a0
  60:	00008067          	ret
  64:	00100693          	li	a3,1
  68:	40b005b3          	neg	a1,a1
  6c:	fd1ff06f          	j	3c <multiply+0x14>
  70:	40a007b3          	neg	a5,a0
  74:	0005ca63          	bltz	a1,88 <multiply+0x60>
  78:	00100693          	li	a3,1
  7c:	fc0590e3          	bnez	a1,3c <multiply+0x14>
  80:	00000513          	li	a0,0
  84:	00008067          	ret
  88:	00000693          	li	a3,0
  8c:	40b005b3          	neg	a1,a1
  90:	fadff06f          	j	3c <multiply+0x14>

Disassembly of section .text.startup:

00000094 <main>:
  94:	14c00313          	li	t1,332
  98:	5fc00e13          	li	t3,1532
  9c:	14c00593          	li	a1,332
  a0:	19030813          	addi	a6,t1,400
  a4:	5fc00513          	li	a0,1532
  a8:	00830e93          	addi	t4,t1,8
  ac:	0005a703          	lw	a4,0(a1)
  b0:	00082783          	lw	a5,0(a6)
  b4:	06074a63          	bltz	a4,128 <main+0x94>
  b8:	00000893          	li	a7,0
  bc:	0607cc63          	bltz	a5,134 <main+0xa0>
  c0:	00000613          	li	a2,0
  c4:	02078463          	beqz	a5,ec <main+0x58>
  c8:	00000613          	li	a2,0
  cc:	0017f693          	andi	a3,a5,1
  d0:	4017d793          	srai	a5,a5,0x1
  d4:	00068463          	beqz	a3,dc <main+0x48>
  d8:	00e60633          	add	a2,a2,a4
  dc:	00171713          	slli	a4,a4,0x1
  e0:	fe0796e3          	bnez	a5,cc <main+0x38>
  e4:	00088463          	beqz	a7,ec <main+0x58>
  e8:	40c00633          	neg	a2,a2
  ec:	00c52023          	sw	a2,0(a0)
  f0:	00458593          	addi	a1,a1,4
  f4:	00480813          	addi	a6,a6,4
  f8:	00450513          	addi	a0,a0,4
  fc:	fbd598e3          	bne	a1,t4,ac <main+0x18>
 100:	32032503          	lw	a0,800(t1)
 104:	000e2683          	lw	a3,0(t3)
 108:	004e2783          	lw	a5,4(t3)
 10c:	32432703          	lw	a4,804(t1)
 110:	40d50533          	sub	a0,a0,a3
 114:	00153513          	seqz	a0,a0
 118:	40e787b3          	sub	a5,a5,a4
 11c:	0017b793          	seqz	a5,a5
 120:	00f50533          	add	a0,a0,a5
 124:	00008067          	ret
 128:	40e00733          	neg	a4,a4
 12c:	00100893          	li	a7,1
 130:	0007d863          	bgez	a5,140 <main+0xac>
 134:	40f007b3          	neg	a5,a5
 138:	0018c893          	xori	a7,a7,1
 13c:	f8dff06f          	j	c8 <main+0x34>
 140:	00000613          	li	a2,0
 144:	f80792e3          	bnez	a5,c8 <main+0x34>
 148:	fa1ff06f          	j	e8 <main+0x54>
