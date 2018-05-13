;*******************************************************************************
;* Program   : TASKER3.ASM
;* Programmer: Tony Papadimitriou <tonyp@acm.org>
;* Purpose   : Demonstrate the simplest (?) preemptive three-task "multitasker"
;*           : Each task takes turns running for 4.1ms at a time
;*           : This one can be extended to more tasks very easily
;* Language  : Motorola/Freescale/NXP 68HC11 Assembly Language (aspisys.com/ASM11)
;* Status    : FREEWARE, Copyright (c) 2018
;* History   : 99.08.18 v1.00 Original
;*           : 99.09.20 v1.01 Added SWI Handler for giving up remaining timeslice
;*           : 99.09.21 v1.02 Added SHADOW11 for simulator runs.
;*           : 00.09.19 v1.03 Added conditional for setting TASKS at assembly time.
;*           : 01.05.05 v1.04 Removed SHADOW11 conditional (newer Shadow11 OK)
;*           : 02.02.14 v1.05 Added TASKSTACKSIZE for defining task stack size
;*           : 06.04.25 v1.06 Added conditionals for upto 5 tasks
;*           : 16.02.18       Refactored for latest ASM11
;*******************************************************************************

#ifdef ?
  #Hint ****************************************************
  #Hint * Possible -D option values are shown here:
  #Hint ****************************************************
  #Hint * DEBUG..... For use with SIM11E
  #Hint * TASKS:n... Set number of tasks to n
  #Hint * INTS...... Interrupts OK inside Print
  #Hint * SWI....... Third task gives up remaining timeslice
  #Hint ****************************************************
  #Fatal Run ASM11 -Dx (where x is any of the above)
#endif
          #ifdef DEBUG
                    #Hint     For SIM11E use only (do NOT burn device)
          #endif
                    #ListOff
                    #Uses     811e2.inc           ;found in ASM11 distribution
                    #ListOn

TASKSTACKSIZE       def       50                  ;default task stack size

;*******************************************************************************
; Macros
;*******************************************************************************

sei                 macro
          #ifndef INTS
                    sei                           ;prevent interrupts
          #endif
                    endm

;-------------------------------------------------------------------------------

cli                 macro
          #ifndef INTS
                    cli                           ;interrupt OK now
          #endif
                    endm

;*******************************************************************************
                    #RAM
;*******************************************************************************

MAXTASKS            def       3                   ;Number of maximum tasks (default)

          #if MAXTASKS < 2
                    #Warning  MAXTASKS ({MAXTASKS}) must be at least two
          #endif

;-------------------------------------------------------------------------------
; Multitasking-related variables and definitions
;-------------------------------------------------------------------------------

?                   macro
TASKSTACK1          equ       STACKTOP-TASKSTACKSIZE
                    mdo       2
TASKSTACK{:mloop}   equ       TASKSTACK{:mloop-1}-TASKSTACKSIZE
                    mloop     MAXTASKS
                    endm

                    @?

;-------------------------------------------------------------------------------

task_index          rmb       1                   ;0, 1, 2, etc.
stack               rmb       2*MAXTASKS          ;Stack for tasks

?FREE_RAM           equ       RAM_END-:pc
?STACKUSED          equ       MAXTASKS*TASKSTACKSIZE

          #if ?STACKUSED > ?FREE_RAM
                    #Error    Not enough RAM for all stacks and variables
          #endif

;*******************************************************************************
                    #ROM
;*******************************************************************************

;*******************************************************************************
; Real Time Interrupt requests come here (does task switching)

RTI_Handler         proc
                    lda       #RTIF.
                    sta       TFLG2               ;Reset the RTI int
;                   bra       SWI_Handler

;*******************************************************************************
; SoftWare Interrupt requests come here (use SWI to give up timeslice)

SWI_Handler         proc
                    ldb       task_index          ;get current task stack pointer
                    ldx       #stack
                    abx:2
                    sts       ,x                  ;Save current SP

                    ldb       task_index          ;point to next task
                    incb                          ;task_index := (task_index + 1) mod MAXTASKS;
                    cmpb      #MAXTASKS           ;higher than max task?
                    blo       Wrap@@
                    clrb                          ;if yes, wrap around to first task
Wrap@@              stb       task_index          ;and save it
                    ldx       #stack
                    abx:2
                    lds       ,x                  ;load new task's SP
                    rti

;*******************************************************************************

TCB                 macro
                    lds       #TASKSTACK{:loop}   ;extra stack
                    ldx       #Task{:loop}        ;point to extra task start address
                    pshx
                    clrx                          ;D, X, and Y start out zeroed
                    pshx:3
                    lda       #S.|X.              ;Initial CCR for task 1
                    psha
                    sts       stack+{:loop-1*2+2}
                    mtop      MAXTASKS
                    endm

;*******************************************************************************

Start               proc
                    clr       task_index          ;initialize to main task

                    @tcb                          ;prepare initial stack frame(s)

          ; Primary (Task0) task's initialization

                    lds       #STACKTOP           ;primary task's stack

          ;---------------------------------------------------------------------
          ; Let's initialize the SCI for polled mode operation at 9600 bps

                    clr       SCCR2
          #ifdef DEBUG
                    clrd                          ;For SIM11E, use fastest bps rate
          #else
                    ldd       #~$30
          #endif
                    std       BAUD
                    lda       #%1100
                    sta       SCCR2               ;Transmitter/Receiver enabled

          ;---------------------------------------------------------------------
          ; Now, let's initialize the timer
          ; Real-time clock initialization (4.1ms RTI @ 2MHz MCU E-Clock)

                    ldx       #REGS
                    bclr      [PACTL,x,%11        ;mask off RTR1:0 bits
                    bset      [TMSK2,x,RTIF.      ;Enable RTI interrupts

                    clrd
                    clrx
                    clry

                    cli                           ;allow multi-tasking from this point on
;                   bra       Task0

;*******************************************************************************
;                   PRIMARY TASK (Task0)
;*******************************************************************************

Task0               proc
Loop@@              ldx       #Msg@@
                    bsr       Print
                    jsr       Delay
                    bra       Loop@@              ;loop forever

Msg@@               fcs       LF,'---Main Task---'

;*******************************************************************************
;                   SECOND TASK (Task1)
;*******************************************************************************

Task1               proc
Loop@@              ldx       #Msg@@
                    bsr       Print
                    bra       Loop@@              ;Cannot use RTS or RTI (independent process)

Msg@@               fcs       LF,'>>>>>>>>>>>>>>>>>>>> Task 2 <<<<<<<<<<<<<<<<<<<<'

;*******************************************************************************
;                   THIRD TASK (Task2)
;*******************************************************************************

Task2               proc
Loop@@              ldx       #Msg@@
                    bsr       Print
          #ifdef SWI
                    swi                           ;Give up remaining timeslice
          #endif
                    bra       Loop@@              ;Cannot use RTS or RTI (independent process)

Msg@@               fcs       LF,'T3'

;*******************************************************************************
;                   ADDITIONAL TASKS (Add as needed)
;*******************************************************************************

Task3               proc
                    swi
                    @...
                    bra       *

;*******************************************************************************

Task4               proc
                    @...
                    bra       *

;*******************************************************************************

Task5               proc
                    @...
                    bra       *

;*******************************************************************************
; Purpose: Send ASCIZ string (pointed to by RegX) to the SCI
; Input  : X -> ASCIZ string
; Output : None
; Note(s):

Print               proc
                    @sei                          ;prevent interrupts
                    pshx
                    psha
Loop@@              lda       ,x                  ;get character
                    beq       Done@@              ;on terminating zero, get out
                    bsr       PutChar             ;everything else, we send to the SCI
                    inx                           ;point to next string character
                    bra       Loop@@              ;repeat
Done@@              pula
                    pulx
                    @cli                          ;interrupt OK now
                    rts

;*******************************************************************************
; Purpose: Send a character to the SCI
; Input  : A = character to send
; Output : None
; Note(s):

PutChar             proc
                    cmpa      #LF
                    bne       Send@@
                    lda       #CR
                    bsr       Send@@
                    lda       #LF
Send@@              tst       SCSR
                    bpl       Send@@
                    sta       SCDR
                    rts

;*******************************************************************************
; Purpose: Delay 0.5ms
; Input  : None
; Output : None
; Note(s):
                              #Cycles
Delay               proc
                    pshx
                    ldx       #DELAY@@
                              #Cycles
Loop@@              dex
                    bne       Loop@@
                              #temp :cycles
                    pulx
                    rts

DELAY@@             equ       BUS_KHZ/2-:cycles-:ocycles/:temp

;*******************************************************************************
                    @vector   Vrti,RTI_Handler    ;Timer interrupt
                    @vector   Vswi,SWI_Handler    ;SoftWare Interrupt
                    @vector   Vcop,Start          ;COP vector
                    @vector   Vcmf,Start          ;CMF vector
                    @vector   Vreset,Start        ;RESET vector
;*******************************************************************************
                    end       :s19crc
