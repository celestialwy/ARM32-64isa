@ systemTimer.s
@ Implements functionalities to handle the internal 
@ clock of the Raspberry

@ Define my Raspberry Pi
        .cpu    cortex-a53
        .fpu    neon-fp-armv8
        .syntax unified         @ modern syntax

@ Constants for assembler
        .equ    PERIPH,0x3f000000   @ RPi 2 & 3 peripherals
        .equ    TIMER_OFFSET,0x3000     @ system timer offset

@ Defined by us:
		.equ    PAGE_SIZE,4096  @ Raspbian memory page
@ Program variables
		.data
fileDesc:
		.word	0
progMem:
		.word	0
@ The program
        .text
        .align  2
        .global getTimestamp
		.global getElapsedTime
		.global delay
		.global initTimer
		.global closeTimer
		.global mmapTOK
        .type   getTimestamp, %function

@ Constant program data
        .section .rodata
        .align  2
device:
        .asciz  "/dev/mem"
devErr:
        .asciz  "Cannot open /dev/mem\n"
memErr:
        .asciz  "Cannot map /dev/mem\n"

@Initializes the timer, mapping its memory
@
initTimer:

		push 	{r5, lr}
		@ Open /dev/mem for read/write and syncing        
        ldr     r0, deviceAddr  @ address of /dev/mem
        bl		openRWSync
        cmp     r0, -1          @ check for error
        bne     memTOK       	@ no error, continue
        ldr     r0, devErrAddr  @ error, tell user
        bl      printf
        b       allDone         @ and end program

 
memTOK: 
@Save the file descriptor
		ldr		r5, fileDescAddr
		str		r0, [r5]		@r0 contains the file descriptor (returned by open)

@ Map the timer
		//ldr		r1, timer
		ldr		r1, =0x3f003000
		bl     	mapMemory
        cmp     r0, -1          @ check for error
        bne     mmapTOK         @ no error, continue
        ldr     r0, memErrAddr 	@ error, tell user
        bl      printf			
        b       closeTDev       @ and close /dev/mem

@ Save the address of the mapping memory in an internal variable
mmapTOK:
		ldr		r1, progMemAddr
		str		r0, [r1]    
		b		allDone

closeTDev:
        mov     r0, r4          @ /dev/mem file descriptor
        bl      close	        @ close the file   
allDone:
		pop		{r5, lr}		
		bx		lr


@ Returns the current timestamp
@ Calling sequence:
@       bl getTimestamp
@ Output:
@		r0 <- lowest 4 bytes of system time(us)
@		r1 <- highest 4 bytes of system time(us)

getTimestamp:
       	ldr		r0, progMemAddr			@ pointer to the address of TIMER regs
		ldr		r0, [r0]				@ address of TIMER regs
		ldrd	r0, r1, [r0, #4]
        bx      lr              		@ return

@ Returns the us that elapsed between the two timestamp in input.
@ Calling sequence:
@		r0 <- lowest 4 bytes of the first time(us)  - the farthest one
@		r1 <- highest 4 bytes of the first time(us) 
@		r2 <- lowest 4 bytes of the second time (us) - the closest one
@		r3 <- highest 4 bytes of the second time (us)
@ Output:
@		r0 <- lowest 4 bytes of the elapsed time (us)
@		r1 <- highest 4 bytes of the elapsed time (us)
getElapsedTime:
		push	{r4, r5}
		subs	r0, r2, r0				@ subtract the lowest part of the two timestamps
	    sbc		r1, r3, r1				@ subtract the highest part of the two timestamps, 
										@ eventually subtracting the borrow generated by the previous sub

		pop		{r4, r5}
		bx		lr

@ Waits r0 us (up to 4294 s)
@ Calling sequence:
@		r0 <- base peripheral address in mapped memory
@       r1 <- us to wait for
@       bl delay

delay:
		push	{r4, r5, r6, r7, r8,  lr} 
		mov 	r7, r0					@ base peripheral address in map memory 
		mov 	r4, r1					@ r4= us to wait for
		bl 		getTimestamp
		mov 	r5, r0					@ r5= lowest part
		mov 	r6, r1					@ r6= highest part

@ Adding the us to wait for
		adds	r5, r5, r4				
		adc		r6, r6, #0

@ Wait until the timer exceeds	r6:r5
delayLoop:	
		mov 	r0, r7					@ base peripheral address in map memory
		bl 		getTimestamp
		cmp 	r1, r6					@ r1=highest system time r6=highest finish time
		cmpeq 	r0, r5					@ if r1=r6 compare r0=lowest system time r5=lowest finish time
		blt		delayLoop				@ if (r1=r6 & r0<r5) | r1<r6

		pop		{r4, r5, r6, r7, r8, lr}
		bx 		lr

@ Unmaps the timer memory and closes the device
closeTimer:
		push	{r4, lr}
		ldr 	r0, progMemAddr
		ldr 	r0, [r0]				@ address of the mapped memory
		ldr 	r1, fileDescAddr
		ldr 	r1, [r1]				@ file descriptor
		bl		closeDevice
		pop		{r4, lr}
		bx 		lr

deviceAddr:
        .word   device
devErrAddr:
        .word   devErr
memErrAddr:
        .word   memErr
timer:
		.word  	PERIPH+TIMER_OFFSET
fileDescAddr:
		.word fileDesc
progMemAddr:
		.word	progMem