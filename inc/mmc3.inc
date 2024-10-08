

.global CurrentBank, NextBank
.global TargetAddrJmp, TargetAddress
.global FarCallCommon, FarCallInit, MapperInit

.include "memory_p.inc"

; MMC3 registers / banking
PRG_FIXED_8 = (1 << 6)
BANK_SELECT = $8000
BANK_DATA   = $8001
NMT_MIRROR  = $a000
RAM_PROTECT = $a001
IRQLATCH    = $c000
IRQRELOAD   = $c001
IRQDISABLE  = $e000
IRQENABLE   = $e001

.macro MAPPER_IRQ_ACK
  sta IRQDISABLE
.endmacro

.macro BankCHR0 bank
  _BANK_INNER bank, 0
.endmacro

.macro BankCHR8 bank
  _BANK_INNER bank, 1
.endmacro

.macro BankCHR10 bank
  _BANK_INNER bank, 2
.endmacro

.macro BankCHR14 bank
  _BANK_INNER bank, 3
.endmacro

.macro BankCHR18 bank
  _BANK_INNER bank, 4
.endmacro

.macro BankCHR1C bank
  _BANK_INNER bank, 5
.endmacro

.macro BankPRGA bank
  _BANK_INNER bank, 7
.endmacro

.macro BankPRGC bank
  _BANK_INNER bank, 6
.endmacro

.macro _BANK_INNER bank, select
.scope
  ; set fixed $8000 bank bit
.if .match(bank, a)
  pha
  lda #select | PRG_FIXED_8
  sta BANK_SELECT
.else
  lda #select | PRG_FIXED_8
  sta BANK_SELECT
.endif
  .if .match(bank, a)
    pla
    sta BANK_DATA
  .elseif .match(bank, x)
    stx BANK_DATA
  .elseif .match(bank, y)
    sty BANK_DATA
  .else
    .if (.match (.left (1, {arg}), #))
      lda #bank
    .else
      lda bank
    .endif
    sta BANK_DATA
  .endif
.endscope
.endmacro

.macro farcall loc, usejmp
.scope
.import loc
.assert .bank(loc) <> .bank(*), error, "Attempting to farcall to the same bank!"
.assert .bank(loc) <> .bank(LOWCODE), error, "Attempting to farcall to the low bank!"
.assert .bank(loc) <> .bank(FIXED), error, "Attempting to farcall to the fixed bank!"
  lda #<loc
  sta TargetAddress
  lda #>loc
  sta TargetAddress+1
  lda #.lobyte(.bank(loc))
  sta NextBank
.ifblank usejmp
  jsr FarCallCommon
.else
  jmp FarCallCommon
.endif
.endscope
.endmacro

.macro far function
.scope
.ident(.concat("farblock_", .string(function))):
  lda CurrentBank
  pha
    lda #7 | PRG_FIXED_8
    sta BankShadow
    sta BANK_SELECT
    lda #.bank(function)
    sta BANK_DATA
    sta CurrentBank
.endmacro

.macro endfar
    lda #7 | PRG_FIXED_8
    sta BankShadow
    sta BANK_SELECT
  pla
  sta BANK_DATA
  sta CurrentBank
.endscope
.endmacro


.macro SetScanlineIRQ line
  .if .match(line, x)
    stx IRQLATCH
    stx IRQRELOAD
    stx IRQENABLE
  .elseif .match(line, y)
    sty IRQLATCH
    sty IRQRELOAD
    sty IRQENABLE
  .else
    .if (.match (.left (1, {arg}), #))
      lda #line
    .else
      lda line
    .endif
    sta IRQLATCH
    sta IRQRELOAD
    sta IRQENABLE
  .endif
.endmacro
