
*= $02
ZPPointer1 .dunion HLWORD
ZPPointer2 .dunion HLWORD
ZPPointer3 .dunion HLWORD
ZPPointer4 .dunion HLWORD
ZPPointer5 .dunion HLWORD
ZPPointer6 .dunion HLWORD
ZPPointer7 .dunion HLWORD
ZPPointer8 .dunion HLWORD
ZPPointer9 .dunion HLWORD
mapPointer .dunion HLWORD
mapPointerCache .dunion HLWORD
activeBitmap .byte ?
VDCReg24Shadow .byte ?
ZPTemp1 .byte ?
ZPTemp2 .byte ?
ZPTemp3 .byte ?
ZPTemp4 .byte ?
ZPTemp5 .byte ?
Map .block
 x .byte ?
 y .byte ?
.bend

;VDC MEM MAP
;    0 - 1b80 Bitmap
; 1b80 - 1ef0 Attributes
; 1f00 - 3a80 Bitmap
; 3a80 - 3df0 Attributes
; 3e00 - 3FFF buffer 512 bytes 
 
kMapWidth = 40
kMapHeight = 12

kScreenTileWidth = 20
kScreenTileHeight = 11

kScreenWidth = 40
kScreenHeight = 22
kBitmap1 = $0000
kAttributes1 = $1b80
kBitmap2 = $1f00
kAttributes2  = $3a80

kAttributeBytes = kScreenWidth * kScreenHeight ; 880
kBitmapBytes = kAttributeBytes * 8 ; 7040 

MODE128 = 1

.if MODE128
	*= $1c01
	.word (+), 10
	.null $9e, "7181"
	+ .word 0
	*=7181
.else
	* = $0801
	.word (+), 10
	.null $9e, "2061"
	+ .word 0
	*=2061
.endif

	#ClearInterupts				 ; disable the interrupts
	inc $d030						 ; enable fast mode
	LDX #$00
   JSR INIT80VDCRegs            ;$E1DC Set Up CRTC Registers
   LDA $D600
   AND #$07
   BEQ bE18A
   LDX #$3B
   JSR INIT80VDCRegs            ;$E1DC Set Up CRTC Registers
bE18A
	;set up 40 col bitmap
	ldy #VDC40ColSetup.length-1	
-	ldx VDC40ColSetup.register,y	
	lda VDC40ColSetup.value,y	
	jsr writeVDCReg	
	dey	
	bpl -	
; now I fill the screen with initial display
; since this is done all at once, I use to have VIC-II formated data, so I converted the VIC-II
; to VDC into a buffer and then I could just pump the data fast to the VDC save settign dest vector
; each byte or row. This is probably the faster way to do it, and I might optimise the row/column 
; plots in the scroll to do this buffer/pump, buts if fast enough for now
; we need to loook at the map, and build a 640 byte buffer in VDC format
	!!mapPointer w= #DummyMap
	!!ZPPointer3 w= #kBitmap1 ; VDC Bitmap offset
	!!ZPPointer6 w= #kAttributes1 ; attributes
	!!ZPTemp4 = #kScreenHeight/2 -1  ; do 10 rows
_copySetLoop
	!!ZPPointer1 w= #buffer
	ldy #0
	sty ZPTemp1
-
	jsr convertMapToPointerGetAttribute
	lda ZPTemp5
	sta AttriBuffer,y ; store the colour data we need
	sta AttriBuffer+1,y
	sta AttriBuffer+40,y
	sta AttriBuffer+41,y
	jsr plotTileToBuffer_ZP5_ZT2  ; plot whole tile
	#ADCBW ZPPointer1,#2 ; move to next tile 
	inc ZPTemp1
	lda ZPTemp1
	tay
	cmp #20
	bne -
	; now we need to copy the char data into VDC memory
	!!ZPPointer1 w= #buffer
	#WRITE_POINTER_VDC #18,ZPPointer3.lo,ZPPointer3.hi
	jsr copyBufferRowToVDC_ZT123
	#ADCWIW ZPPointer3,kScreenWidth*16,ZPPointer3 ; offset this down to the next chunk
	#ADCBW ZPPointer6,#kScreenWidth*2 ; move down two rows on the Attributes
	#ADCBW mapPointer,#kMapWidth ; next row
	dec ZPTemp4
	bpl _copySetLoop

	!!activeBitmap = #0
	!!Map.x = #0
	!!Map.y = #0
	!!mapPointer w= #DummyMap+(kScreenWidth/2) -1 

; Main scroll loop
; not that optimal, but easy to follow
LOOP
	lda $dc00
	and #8+2
	bne + 
		jsr shiftDownRight
		jmp LOOP
+	lda $dc00	
	and #4+2	
	bne +	
		jsr shiftDownLeft
		jmp LOOP
+	lda $dc00
	and #8+1
	bne +
		jsr shiftUpRight
		jmp LOOP
+	lda $dc00
	and #4+1
	bne +
		jsr shiftUpLeft
		jmp LOOP
+  lda $dc00
	and #$8
	bne +
	jsr shiftRight
	jmp _UD
+	lda $dc00
	and #$4
	bne +
	jsr shiftLeft	
_UD	
+	lda $dc00	
	and #$2	
	bne +	
	jsr shiftDown	
+	lda $dc00
	and #$1
	bne +
	jsr shiftUp
+	jmp LOOP

;	inc $d020
  jmp loop


;data to set the VDC to 40 col mode
VDC40ColSetup .block
					;reg, value
	_values := [(0,63),
					(1,kScreenWidth),
					(2,55),
					(3,69),
					(6,kScreenHeight),
				   (22,$89),
				   (25,215),
				   (27,0),
				   (34,63),
				   (35,52),
				   (20,>kAttributes1),
				   (21,<kAttributes1),
				   (12,>kBitmap1),
				   (13,<kBitmap1)
					]
	length = len(_values)
	register .byte _values[:,0] 
	value .byte _values[:,1]
.bend

AddAndWrapMapX
;adds a to Map.x wrapping arround
	clc
	adc Map.x
	cmp #kMapWidth
	bcc +
		sec
		sbc #kMapWidth
+	sta Map.x
	rts
	
SubAndWrapMapX_ZT1
;subs a from Map.x wrapping arround
;trashes ZPTemp1
	sta ZPTemp1
	sec
	lda Map.x
	sbc ZPTemp1
	cmp #kMapWidth
	bcc +
		clc
		adc #kMapWidth
+	sta Map.x
	rts
	
AddAndWrapMapY
;adds a to Map.y wrapping arround
	clc
	adc Map.y
	cmp #kMapHeight
	bcc +
		sec
		sbc #kMapHeight
+	sta Map.y
	rts
	
SubAndWrapMapY_ZT1
;subs a from Map.y wrapping arround
;trashes ZPTemp1
	sta ZPTemp1
	sec
	lda Map.y
	sbc ZPTemp1
	cmp #kMapHeight
	bcc +
		clc
		adc #kMapHeight
+	sta Map.y
	rts

restoreMapXYFromStack	
;loads Map.x,Map.y from the stack
;assumes they are before the rts
	tsx	
	lda $101+2,x	
	sta Map.y	
	lda $102+2,x	
	sta Map.x ;12 + 4*3 = 24	
	rts
	
setP3fromMapXY_ZPP4
;This will set ZPPointer3 to Map.y *64 + Map.x
;trashes ZPPpointer4
	lda #$00
	sta ZPPointer3.hi
	lda Map.y ; x64 or hi swap / 4
	asl a ; x2
	rol ZPPointer3.hi
	asl a ; x4
	rol ZPPointer3.hi
	asl a ; x8
	rol ZPPointer3.hi
	sta ZPPointer4.lo
	lda ZPPointer3.hi
	sta ZPPointer4.hi ; cache x8
	lda ZPPointer4.lo
	asl a ; x16
	rol ZPPointer3.hi
	asl a ; x32
	rol ZPPointer3.hi
	clc
	adc ZPPointer4.lo
	sta ZPPointer3.lo
	lda ZPPointer3.hi
	adc ZPPointer4.hi
	clc
	adc #>DummyMap
	sta ZPPointer3.hi
	#ADCBW ZPPointer3, Map.x
	#ADCBW ZPPointer3, #<DummyMap
	rts
	
	
SetP1P2FromMapTileXY
	; ZPTemp1 = X unchanged
	; ZPTemp2 = Y unchanged
	; returns
   ; ZPPointer 1 = TL Bitmap
   ; ZPPointer 2 = TL Screen
   ; ZPPointer4 TRASHED
   ldx ZPTemp2
   #LIW BitmapYTableTile,x,ZPPointer1
   lda #0
   sta ZPPointer4.hi
   lda ZPTemp1
   asl a
   sta ZPPointer4.lo
   #ADCW ZPPointer1, ZPPointer4, ZPPointer1 ; P1 = Bitmap + y*640 + x*16
   #LIW ScreenYTableTile,x,ZPPointer2
   lda ZPTemp1
   asl a ; 2x
   adc ZPPointer2.lo
   sta ZPPointer2.lo
   bcc +
   	inc ZPPointer2.hi ; P2 = Screen + y*80 + x*2
+  rts	
   
shiftRight
;shift the screen to the left, so it looks like it goes to right
	lda #kScrollRightIndex
	jsr doDMAForDirection_ZT1
	; move the map Pointer over 
	lda #1
	jsr AddAndWrapMapX
	pha
	lda Map.Y
	pha ; save Map.X and Y
	lda #kScreenTileWidth-1
	jsr AddAndWrapMapX ; offset to the side of the map
	!!ZPTemp1 = #kScreenTileWidth-1
	!!ZPTemp2 = #0
	jsr plotColumnBitmap	
;	!!Map.X -= #19 ; move it back to the left edge
	jmp restoreMapValuesSetIOWaitAndFlip

plotColumnBitmap
;ZPTemp1 = X offset
;ZPTemp2 = Y offset
;MapX,MapY = should be set for read positon of new data
_loop	 
	jsr setP3fromMapXY_ZPP4		;get the map tile
	jsr SetP1P2FromMapTileXY	;set the bitmap and attributes pointer
	ldx activeBitmap
	lda ZPPointer1.hi
	clc
	adc BitMapHiOffset,x			; adjust for active bitmap
	sta ZPPointer1.hi
	lda ZPPointer2.hi
	clc
	adc BitMapHiOffset,x
	sta ZPPointer2.hi
	jsr DrawMapTileOnScreen_ZP4_ZT5		; draw the tile
	lda #1
	jsr AddAndWrapMapY			; move down 1 
	inc ZPTemp2
	!!if ZPTemp2 != #kScreenTileHeight then _loop
	rts

shiftLeft
;shift the screen to the right
	lda #kScrollLeftIndex
	jsr doDMAForDirection_ZT1
	; move the map Pointer over 
	lda #1
	jsr SubAndWrapMapX_ZT1
	pha
	lda Map.Y
	pha
	!!ZPTemp1 = #0
	!!ZPTemp2 = #0
	jsr plotColumnBitmap	
restoreMapValuesSetIOWaitAndFlip
	pla
	sta Map.Y 
	pla
	sta Map.X ; restore Map.X and Y
-  lda $d600
	and #%00100000 ; make sure we are out of VBlank
	bne -
	;toggle the artributes
	ldy activeBitmap
	bne +
		#WRITE_16IMMEDIATE_VDC #20,kAttributes2
		jmp ++
+	#WRITE_16IMMEDIATE_VDC #20,kAttributes1
+
	; wait for vblank
-	lda $d600
	and #%00100000
	beq -
	; flip the screen
	ldy activeBitmap
	bne +
		#WRITE_16IMMEDIATE_VDC #12,kBitmap2		
		jmp ++
+	#WRITE_16IMMEDIATE_VDC #12,kBitmap1
+		
	!!activeBitmap ^= #1
	rts

shiftUp
;shift the screen down
	lda #kScrollUpIndex
	jsr doDMAForDirection_ZT1
	; move the map Pointer over 
	lda Map.x
	pha
	lda #1
	jsr SubAndWrapMapY_ZT1
	pha
	!!ZPTemp1 = #0
	!!ZPTemp2 = #0
	jsr plotRowBitmap
	jmp restoreMapValuesSetIOWaitAndFlip	

plotRowBitmap
;this will plot across the screen
_loop	 
	jsr setP3fromMapXY_ZPP4		; get pointer to map tile
	jsr SetP1P2FromMapTileXY	; get pointers to bitmap and attributes
	ldx activeBitmap
	lda ZPPointer1.hi
	clc
	adc BitMapHiOffset,x			; adjust for active bitmap
	sta ZPPointer1.hi
	lda ZPPointer2.hi
	clc
	adc BitMapHiOffset,x
	sta ZPPointer2.hi
	jsr DrawMapTileOnScreen_ZP4_ZT5		; draw the tile
	lda #1
	jsr AddAndWrapMapX			; move over one
	inc ZPTemp1
	!!if ZPTemp1 != #kScreenTileWidth then _loop
	rts	
		
shiftDown
	;shift the screen up
	lda #kScrollDownIndex
	jsr doDMAForDirection_ZT1
	; move the map Pointer over 
	lda Map.x
	pha
	lda #1
	jsr AddAndWrapMapY
	pha
	!!ZPTemp1 = #0
	!!ZPTemp2 = #kScreenTileHeight-1
	lda #kScreenTileHeight-1
	jsr AddAndWrapMapY
	jsr plotRowBitmap
	jmp restoreMapValuesSetIOWaitAndFlip	

shiftDownRight
	;shift the screen up and left
	lda #kScrollDownRightIndex
	jsr doDMAForDirection_ZT1
	; move the map Pointer over 
	lda #1
	jsr AddAndWrapMapX
	pha
	lda #1
	jsr AddAndWrapMapY 
	pha
	lda #kScreenTileWidth-1
	jsr AddAndWrapMapX
	!!ZPTemp1 = #kScreenTileWidth-1
	!!ZPTemp2 = #0
	jsr plotColumnBitmap
	jsr restoreMapXYFromStack		
	lda #kScreenTileHeight-1	
	jsr AddAndWrapMapY	
	!!ZPTemp1 = #0
	!!ZPTemp2 = #kScreenTileHeight-1	
	jsr plotRowBitmap	
	jmp restoreMapValuesSetIOWaitAndFlip

shiftDownLeft
	;shift the screen up and right
	lda #kScrollDownLeftIndex
	jsr doDMAForDirection_ZT1
	; move the map Pointer over 
	lda #1
	jsr SubAndWrapMapX_ZT1
	pha
	lda #1
	jsr AddAndWrapMapY
	pha
	!!ZPTemp1 = #0
	!!ZPTemp2 = #0
	jsr plotColumnBitmap
	jsr restoreMapXYFromStack	
	lda #kScreenTileHeight-1
	jsr AddAndWrapMapY ; offset to the side of the map
	!!ZPTemp1 = #0
	!!ZPTemp2 = #kScreenTileHeight-1
	jsr plotRowBitmap	
	jmp restoreMapValuesSetIOWaitAndFlip	

shiftUpRight		
	; shift the screen down and left
	lda #kScrollUpRightIndex
	jsr doDMAForDirection_ZT1
	; move the map Pointer over 
	lda #1
	jsr AddAndWrapMapX
	pha
	lda #1
	jsr SubAndWrapMapY_ZT1
	pha
	lda #kScreenTileWidth-1
	jsr AddAndWrapMapX
	!!ZPTemp1 = #kScreenTileWidth-1
	!!ZPTemp2 = #0
	jsr plotColumnBitmap
	jsr restoreMapXYFromStack		
	!!ZPTemp1 = #0
	!!ZPTemp2 = #0
	jsr plotRowBitmap	
	jmp restoreMapValuesSetIOWaitAndFlip

shiftUpLeft		
	;shift the screen down and right	
	lda #kScrollUpLeftIndex
	jsr doDMAForDirection_ZT1
	; move the map Pointer over 
	lda #1
	jsr SubAndWrapMapX_ZT1
	pha
	lda #1
	jsr SubAndWrapMapY_ZT1
	pha
	!!ZPTemp1 = #0
	!!ZPTemp2 = #0
	jsr plotColumnBitmap
	jsr restoreMapXYFromStack		
	!!ZPTemp1 = #0
	!!ZPTemp2 = #0
	jsr plotRowBitmap	
	jmp restoreMapValuesSetIOWaitAndFlip		
			
doDMAForDirection_ZT1
;this will shift the bitmap, based upon the passed in index
;it will handle active bitmap 
	ldy activeBitmap
	beq +
		clc
		adc #kOtherActiveDelta
+	tay
	; set Bitmap Scroll data
	ldx #24
	lda #128 ; copy
	sta VDCReg24Shadow ; make sure our DMA is copy
	jsr writeVDCReg
	; set source
	lda CopyScrollSetUps.bitmap.src.hi,y
	ldx #32
	stx $d600	
-	bit $d600	
	bpl -	
	sta $d601	
	inx ;33	
	stx $d600	
	lda CopyScrollSetUps.bitmap.src.lo,y	
	sta $d601	
	; set Dest	
	lda CopyScrollSetUps.bitmap.dest.hi,y
	ldx #18
	stx $d600	
-	bit $d600	
	bpl -	
	sta $d601	
	inx ;19	
	stx $d600	
	lda CopyScrollSetUps.bitmap.dest.lo,y	
	sta $d601	
		
	lda CopyScrollSetUps.bitmap.pages,y	
	sty ZPTemp1	; save offset index
	tay	
	lda #255
	ldx #30
-
	jsr writeVDCReg ; do DMA
	dey 
	bpl -
	ldy ZPTemp1 ; restore offset index
	lda CopyScrollSetUps.bitmap.extra,y ; do extra bytes
	beq + ; skip if 0 to do
		jsr writeVDCReg
+ 
	; attributes
	; set source
	lda CopyScrollSetUps.screen.src.hi,y
	ldx #32
	stx $d600	
-	bit $d600	
	bpl -	
	sta $d601	
	inx ; 33	
	stx $d600	
	lda CopyScrollSetUps.screen.src.lo,y	
	sta $d601	
	; set Dest	
	lda CopyScrollSetUps.screen.dest.hi,y
	ldx #18
	stx $d600	
-	bit $d600	
	bpl -	
	sta $d601	
	inx ; 19	
	stx $d600	
	lda CopyScrollSetUps.screen.dest.lo,y	
	sta $d601	
		
	lda CopyScrollSetUps.screen.pages,y	
	sty ZPTemp1	
	tay	
	lda #255
	ldx #30
-
	jsr writeVDCReg ; do DMA
	dey 
	bpl -
	ldy ZPTemp1 
	lda CopyScrollSetUps.screen.extra,y ; do extra bytes
	beq +
		jsr writeVDCReg
+ rts

BitMapHiOffset .byte >kBitmap2,$00	

kScrollRightIndex = 0
kScrollLeftIndex = 1
kScrollUpIndex = 2
kScrollDownIndex = 3
kScrollDownRightIndex = 4
kScrollDownLeftIndex = 5
kScrollUpRightIndex = 6
kScrollUpLeftIndex = 7

kOtherActiveDelta = 8

CopyScrollSetUps .block
	; src, dest, pages, extra, src, dest, pages, src
	_normal  := [[kBitmap1+2,kBitmap2,$1d,$00,
					 kAttributes1+2,kAttributes2,$03,$00]] ; right
	_normal ..= [[kBitmap1,kBitmap2+2,$1d,$00,
					  kAttributes1,kAttributes2+2,$03,$00]] ; left
	_normal ..= [[kBitmap1,kBitmap2+640,$1a,$80,
					  kAttributes1,kAttributes2+80,$02,$70]] ;up
	_normal ..= [[kBitmap1+640,kBitmap2,$1a,$80,
					  kAttributes1+80,kAttributes2,$02,$70]] ; down
	_normal ..= [[kBitmap1+642,kBitmap2,$1a,$80,
					  kAttributes1+82,kAttributes2,$02,$70]] ; down right
	_normal ..= [[kBitmap1+640,kBitmap2+2,$1a,$80,
					  kAttributes1+80,kAttributes2+2,$02,$70]] ; down left				
	_normal ..= [[kBitmap1,kBitmap2+638,$1a,$80,
					  kAttributes1,kAttributes2+78,$02,$70]] ; up right								
	_normal ..= [[kBitmap1,kBitmap2+642,$1a,$80,
					  kAttributes1,kAttributes2+82,$02,$70]] ; up left													
																	
	_otherActive :=  [[kBitmap2+2,kBitmap1,$1d,$00,
							 kAttributes2+2,kAttributes1,$03,$00]] ; right other
	_otherActive ..= [[kBitmap2,kBitmap1+2,$1d,$00,
							 kAttributes2,kAttributes1+2,$03,$00]] ; left other
	_otherActive ..= [[kBitmap2,kBitmap1+640,$1a,$00,
							 kAttributes2,kAttributes1+80,$02,$70]] ;up other
	_otherActive ..= [[kBitmap2+640,kBitmap1,$1a,$80,
							 kAttributes2+80,kAttributes1,$02,$70]] ;down other
	_otherActive ..= [[kBitmap2+642,kBitmap1,$1a,$80,
					   	 kAttributes2+82,kAttributes1,$02,$70]] ; down right other
	_otherActive ..= [[kBitmap2+640,kBitmap1+2,$1a,$80,
					  		 kAttributes2+80,kAttributes1+2,$02,$70]] ; down left other
	_otherActive ..= [[kBitmap2,kBitmap1+638,$1a,$80,
					 		 kAttributes2,kAttributes1+78,$02,$70]] ; up right
	_otherActive ..= [[kBitmap2,kBitmap1+642,$1a,$80,
					 		 kAttributes2,kAttributes1+82,$02,$70]] ; up left
	
	_both := _normal.._otherActive
	bitmap .block
		src .block
			lo .byte <(CopyScrollSetUps._both[:,0])
			hi .byte >(CopyScrollSetUps._both[:,0])
		.bend
		dest .block
			lo .byte <(CopyScrollSetUps._both[:,1])
			hi .byte >(CopyScrollSetUps._both[:,1])
		.bend
		pages .byte CopyScrollSetUps._both[:,2]
		extra .byte CopyScrollSetUps._both[:,3]
	.bend
	screen .block
		src .block
			lo .byte <(CopyScrollSetUps._both[:,4])
			hi .byte >(CopyScrollSetUps._both[:,4])
		.bend
		dest .block
			lo .byte <(CopyScrollSetUps._both[:,5])
			hi .byte >(CopyScrollSetUps._both[:,5])
		.bend
		pages .byte CopyScrollSetUps._both[:,6]
		extra .byte CopyScrollSetUps._both[:,7]
	.bend
	
.bend	

convertMapToPointerGetAttribute
;this will convert the tile pointed to by MapPointer+y into a  
;pointer to the tile and will return the attribute value in ZPTemp5 
;returns 
;ZPTemp5 Attribute value 
;ZPPointer4 Pointer to the start of the tile data 
	lda (mapPointer),y 		; read map
	tax 							; x = tile 
	tya						
	asl a
	tay							; y = y *2
	lda bitmapAttributes,x  
	sta ZPTemp5					;store the attributes
	txa							; a = tile num
	; this is the map tile
	asl a
	asl a ; x4 to get the char
	asl a
	asl a
	asl a ; x8 to get the ram location This will need to go to 16 bit at some point
	clc
	adc #<bitmapTiles
	sta ZPPointer4.lo ; tiledata ptr
	lda #>bitmapTiles
	adc #0
	sta ZPPointer4.hi ; tiledata ptr	
	rts	
	
plotTileToBuffer_ZP5_ZT2 
; this will plot a VDC format tile to the buffer
;ZPPointer1 = TL of tile pos in Buffer
;ZPPointer4 = TL of tile data
	lda ZPPointer1.lo
	sta ZPPointer5.lo
	lda ZPPointer1.hi
	sta ZPPointer5.hi ; cache ZP1
	ldy #0
-	lda (ZPPointer4),y ; read first byte
	sty ZPTemp2
	ldy #0
	sta (ZPPointer5),y ; store in buffer
	inc ZPTemp2
	ldy ZPTemp2
	lda (ZPPointer4),y ; get next byte
	ldy #1
	sta (ZPPointer5),y ; store in buffer
	#ADCBW ZPPointer5,#40 ; next line
	ldy ZPTemp2
	iny
	cpy #32
	bne -
	rts

DrawMapTileOnScreen_ZP4_ZT5
	; ZPPointer1 = TL of bitmap to draw
	; ZPPointer2 = TL of screen to draw
	; ZPPointer3 = Pointer to Map tile num
	ldy #0
	sty ZPPointer4.hi
	lda (ZPPointer3),y ; get tile
	pha ; save the tile number
	asl a
	asl a ; x4
	asl a 
	rol ZPPointer4.hi ; x8
	asl a
	rol ZPPointer4.hi ; x16
	asl a
	rol ZPPointer4.hi ;x32
	clc 
	adc #<SrcTiles
	sta ZPPointer4.lo
	lda ZPPointer4.hi
	adc #>SrcTiles
	sta ZPPointer4.hi ; Pointer 4 now holds pointer to the tile
	jsr plotCharToVdc_ZT4 ; draw the tile
	pla ; restore the tile num
	tax
	lda bitmapAttributes,x ; get attribute
	sta ZPTemp5
	jmp plotAttributesToVDC
	
plotCharToVdc_ZT4
	; ZPPointer1 should hold dest address
	; ZPPointer4 should hold the char data
	ldy #0
	sty ZPTemp4
_l1
	#WRITE_POINTER_VDC #18, ZPPointer1.lo,ZPPointer1.hi
	ldy ZPTemp4
	lda (ZPPointer4),y
	ldx #31
	jsr writeVDCReg
	iny
	lda (ZPPointer4),y
	jsr writeVDCReg ; #31
	#ADCBW ZPPointer1,#kScreenWidth
	iny
	sty ZPTemp4
	cpy #32 ; num bites in tile
	bne _l1
	rts	

plotAttributesToVDC
; this will store the value in ZPTemp5, 4 times in 2x2
; to the location help in ZPPointer2
	#WRITE_POINTER_VDC #18, ZPPointer2.lo,ZPPointer2.hi
	lda ZPTemp5
	ldx #31
	jsr writeVDCReg
	jsr writeVDCReg
	#ADCBW ZPPointer2,#kScreenWidth
	#WRITE_POINTER_VDC #18, ZPPointer2.lo,ZPPointer2.hi
	lda ZPTemp5
	ldx #31
	jsr writeVDCReg
	jsr writeVDCReg	
	#ADCBW ZPPointer2,#kScreenWidth	
	rts	

copyBufferRowToVDC_ZT123
;This will copy the buffer to the VDC
;VDC should be primed to the bitmap locations before calling
;ZPPointer1 points to start of Buffer data, it will be advanced during operation
;ZPPointer6 holds the attribute dest location
	!!ZPTemp2 = #15 ; do 16 rows
_copyRow
	!!ZPTemp1 = #kScreenWidth-1 ; do 40 bytes 
	ldy #0
	sty ZPTemp3
_copyBuffer
	ldy ZPTemp3
	lda (ZPPointer1),y
	ldx #31
	jsr writeVDCReg
	inc ZPTemp3
	dec ZPTemp1
	bpl _copyBuffer
	#ADCBW ZPPointer1,#40
	dec ZPTemp2
	bpl _copyRow
	; now we copy the attributes	
	!!ZPTemp1 = #00
	#WRITE_POINTER_VDC #18,ZPPointer6.lo,ZPPointer6.hi
_copyAttrbuffer
	ldy ZPTemp1
	lda AttriBuffer,y
	ldx #31
	jsr writeVDCReg
	inc ZPTemp1
	lda ZPTemp1
	cmp #kScreenWidth*2
	bne _copyAttrbuffer
	rts
	
writeVDCReg	
; a = value	
; x = egister	
	stx $d600	
-	bit $d600	
	bpl -	
	sta $d601	
	rts	
		
WRITE_POINTER_VDC .macro		
	lda \2
	ldy \3
	ldx \1
	jsr writeVDCRegP
.endm

WRITE_16IMMEDIATE_VDC .macro
	lda #<\2
	ldy #>\2
	ldx \1
	jsr writeVDCRegP
.endm

writeVDCRegP	
; a = lo value	
; y = hi value	
; x = start register	
	stx $d600	
-	bit $d600	
	bpl -	
	sty $d601	
	inx	
	stx $d600	
	sta $d601	
	rts	

;lookup tables for Y to line start in VDC bitmap
BitmapYTableTile .block
	- = range(kBitmap1, kBitmap1+8000, 640)
	lo .byte <(-)
	hi .byte >(-)
.bend

;lookup tables for Y to line start in VDC attributes
ScreenYTableTile .block
	- = range(kAttributes1, kAttributes1+1000, 80)
	lo .byte <(-)
	hi .byte >(-)
.bend


;copied from C128 KERNAL, so you can boot this from the C64 side, say EF3 cart etc
INIT80VDCRegs           LDY VDCDEFTBL,X
                        BMI bE1EE
                        INX 
                        LDA VDCDEFTBL,X
                        INX 
                        STY $D600
                        STA $D601
                        BPL INIT80VDCRegs
bE1EE                   INX 
                        RTS 


VDCDEFTBL               .BYTE $00,$7E,$01,$50,$02,$66,$03,$49
                        .BYTE $04,$20,$05,$00,$06,$19,$07,$1D
                        .BYTE $08,$00,$09,$07,$0A,$20,$0B,$07
                        .BYTE $0C,$00,$0D,$00,$0E,$00,$0F,$00
                        .BYTE $14,$08,$15,$00,$17,$08,$18,$20
                        .BYTE $19,$40,$1A,$F0,$1B,$00,$1C,$20
                        .BYTE $1D,$07,$22,$7D,$23,$64,$24
pE32F                   .BYTE $05,$16,$78,$FF,$19,$47,$FF,$04
                        .BYTE $26,$07,$20,$FF

        ; prints a 32 bit value to the screen
printdec
        jsr hex2dec

        ldx #9
l1      lda result,x
        bne l2
        dex             ; skip leading zeros
        bne l1

l2      lda result,x
        ora #$30
        jsr $ffd2		
        dex
        bpl l2
        rts

        ; converts 10 digits (32 bit values have max. 10 decimal digits)
hex2dec
        ldx #0
l3      jsr div10
        sta result,x
        inx
        cpx #10
        bne l3
        rts

        ; divides a 32 bit value by 10
        ; remainder is returned in akku
div10
        ldy #32         ; 32 bits
        lda #0
        clc
l4      rol
        cmp #10
        bcc skip
        sbc #10
skip    rol value
        rol value+1
        rol value+2
        rol value+3
        dey
        bpl l4
        rts

value   .byte $ff,$ff,$ff,$ff

result  .byte 0,0,0,0,0,0,0,0,0,0

		
bitmapTiles
SrcTiles
.binary "charsVDC.bin"

bitmapAttributes
.byte $54,$23,$ce,$5d

.align $100
;map
DummyMap
.binary "map.bin"


buffer .fill 640*2
AttriBuffer .fill 80

*=$ffd2
CharOut ;&&ForcedStop don't follow this address

ClearInterupts .macro
	sei
	lda #$7f
	sta $dc0d		 ;turn off all types of cia irq/nmi.
	sta $dd0d
	lda $dc0d
	lda $dd0d
	lda #$ff
	sta $D019
	lda #$00
	sta $D01a
	sta $dc0e
	sta $dc0f
	sta $dd0e
	sta $dd0f
	lda $d01e
	lda $d01f
.endm

ADCBW .macro
	clc
	lda \1
	adc \2
	sta \1
	bcc +
	inc (\1)+1
+
.endm

HLWord .union
 .word ?
 .struct
 	lo .byte ?
 	hi .byte ?
 .ends
.endu

ADCWIW .segment		
	lda \1		
	clc		
	adc #<(\2)		
	sta \3		
	lda \1+1		
	adc #>(\2)		
	sta \3+1		
.endm

LIW .macro
	lda \1.lo,\2
	sta \3.lo
	lda \1.hi,\2
	sta \3.hi
.endm

ADCW .macro
	clc
	lda \1
	adc \2
	sta \1
	lda (\1)+1
	adc (\2)+1
	sta (\1)+1
.endm
