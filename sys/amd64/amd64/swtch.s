/*-
 * Copyright (c) 1990 The Regents of the University of California.
 * All rights reserved.
 *
 * This code is derived from software contributed to Berkeley by
 * William Jolitz.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. All advertising materials mentioning features or use of this software
 *    must display the following acknowledgement:
 *	This product includes software developed by the University of
 *	California, Berkeley and its contributors.
 * 4. Neither the name of the University nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 * $FreeBSD$
 */

#include <machine/asmacros.h>

#include "assym.s"

/*****************************************************************************/
/* Scheduling                                                                */
/*****************************************************************************/

	.text

/*
 * cpu_throw()
 *
 * This is the second half of cpu_swtch(). It is used when the current
 * thread is either a dummy or slated to die, and we no longer care
 * about its state.  This is only a slight optimization and is probably
 * not worth it anymore.  Note that we need to clear the pm_active bits so
 * we do need the old proc if it still exists.
 * %rdi = oldtd
 * %rsi = newtd
 */
ENTRY(cpu_throw)
	xorq	%rax, %rax
	movl	PCPU(CPUID), %eax
	testq	%rdi,%rdi			/* no thread? */
	jz	1f
	/* release bit from old pm_active */
	movq	TD_PROC(%rdi), %rdx		/* oldtd->td_proc */
	movq	P_VMSPACE(%rdx), %rdx		/* proc->p_vmspace */
	btrq	%rax, VM_PMAP+PM_ACTIVE(%rdx)	/* clear old */
1:
	movq	TD_PCB(%rsi),%rdx		/* newtd->td_proc */
	movq	PCB_CR3(%rdx),%rdx
	movq	%rdx,%cr3			/* new address space */
	/* set bit in new pm_active */
	movq	TD_PROC(%rsi),%rdx
	movq	P_VMSPACE(%rdx), %rdx
	btsq	%rax, VM_PMAP+PM_ACTIVE(%rdx)	/* set new */
	jmp	sw1

/*
 * cpu_switch(old, new)
 *
 * Save the current thread state, then select the next thread to run
 * and load its state.
 * %rdi = oldtd
 * %rsi = newtd
 */
ENTRY(cpu_switch)

	/* Switch to new thread.  First, save context. */
#ifdef INVARIANTS
	testq	%rdi,%rdi			/* no thread? */
	jz	badsw2				/* no, panic */
#endif

	movq	TD_PCB(%rdi),%rdx

	movq	(%rsp),%rax			/* Hardware registers */
	movq	%rax,PCB_RIP(%rdx)
	movq	%rbx,PCB_RBX(%rdx)
	movq	%rsp,PCB_RSP(%rdx)
	movq	%rbp,PCB_RBP(%rdx)
	movq	%r12,PCB_R12(%rdx)
	movq	%r13,PCB_R13(%rdx)
	movq	%r14,PCB_R14(%rdx)
	movq	%r15,PCB_R15(%rdx)
	pushfq					/* PSL */
	popq	PCB_RFLAGS(%rdx)

	/* have we used fp, and need a save? */
	cmpq	%rdi,PCPU(FPCURTHREAD)
	jne	1f
	pushq	%rdi
	pushq	%rsi
	addq	$PCB_SAVEFPU,%rdx		/* h/w bugs make saving complicated */
	movq	%rdx, %rdi
	call	npxsave				/* do it in a big C function */
	popq	%rsi
	popq	%rdi
1:

	/* Save is done.  Now fire up new thread. Leave old vmspace. */
#ifdef INVARIANTS
	testq	%rsi,%rsi			/* no thread? */
	jz	badsw3				/* no, panic */
#endif
	movq	TD_PCB(%rsi),%rdx
	xorq	%rax, %rax
	movl	PCPU(CPUID), %eax

	/* switch address space */
	movq	PCB_CR3(%rdx),%rdx
	movq	%rdx,%cr3			/* new address space */

	/* Release bit from old pmap->pm_active */
	movq	TD_PROC(%rdi), %rdx		/* oldproc */
	movq	P_VMSPACE(%rdx), %rdx
	btrq	%rax, VM_PMAP+PM_ACTIVE(%rdx)	/* clear old */

	/* Set bit in new pmap->pm_active */
	movq	TD_PROC(%rsi),%rdx		/* newproc */
	movq	P_VMSPACE(%rdx), %rdx
	btsq	%rax, VM_PMAP+PM_ACTIVE(%rdx)	/* set new */

sw1:
	/*
	 * At this point, we've switched address spaces and are ready
	 * to load up the rest of the next context.
	 */
	movq	TD_PCB(%rsi),%rdx

	/* Update the TSS_RSP0 pointer for the next interrupt */
	leaq	-16(%rdx), %rbx
	movq	%rbx, common_tss + COMMON_TSS_RSP0

	/* Restore context. */
	movq	PCB_RBX(%rdx),%rbx
	movq	PCB_RSP(%rdx),%rsp
	movq	PCB_RBP(%rdx),%rbp
	movq	PCB_R12(%rdx),%r12
	movq	PCB_R13(%rdx),%r13
	movq	PCB_R14(%rdx),%r14
	movq	PCB_R15(%rdx),%r15
	movq	PCB_RIP(%rdx),%rax
	movq	%rax,(%rsp)
	pushq	PCB_RFLAGS(%rdx)
	popfq

	movq	%rdx, PCPU(CURPCB)
	movq	%rsi, PCPU(CURTHREAD)		/* into next thread */

	ret

#ifdef INVARIANTS
badsw1:
	pushq	%rax
	pushq	%rcx
	pushq	%rdx
	pushq	%rbx
	pushq	%rbp
	pushq	%rsi
	pushq	%rdi
	pushq	%r8
	pushq	%r9
	pushq	%r10
	pushq	%r11
	pushq	%r12
	pushq	%r13
	pushq	%r14
	pushq	%r15
	pushq	$sw0_1
	call	panic
sw0_1:	.asciz	"cpu_throw: no newthread supplied"

badsw2:
	pushq	%rax
	pushq	%rcx
	pushq	%rdx
	pushq	%rbx
	pushq	%rbp
	pushq	%rsi
	pushq	%rdi
	pushq	%r8
	pushq	%r9
	pushq	%r10
	pushq	%r11
	pushq	%r12
	pushq	%r13
	pushq	%r14
	pushq	%r15
	pushq	$sw0_2
	call	panic
sw0_2:	.asciz	"cpu_switch: no curthread supplied"

badsw3:
	pushq	%rax
	pushq	%rcx
	pushq	%rdx
	pushq	%rbx
	pushq	%rbp
	pushq	%rsi
	pushq	%rdi
	pushq	%r8
	pushq	%r9
	pushq	%r10
	pushq	%r11
	pushq	%r12
	pushq	%r13
	pushq	%r14
	pushq	%r15
	pushq	$sw0_3
	call	panic
sw0_3:	.asciz	"cpu_switch: no newthread supplied"
#endif

noswitch:	.asciz	"cpu_switch: called!"
nothrow:	.asciz	"cpu_throw: called!"
/*
 * savectx(pcb)
 * Update pcb, saving current processor state.
 */
ENTRY(savectx)
	/* Fetch PCB. */
	movq	%rdi,%rcx

	/* Save caller's return address. */
	movq	(%rsp),%rax
	movq	%rax,PCB_RIP(%rcx)

	movq	%cr3,%rax
	movq	%rax,PCB_CR3(%rcx)

	movq	%rbx,PCB_RBX(%rcx)
	movq	%rsp,PCB_RSP(%rcx)
	movq	%rbp,PCB_RBP(%rcx)
	movq	%r12,PCB_R12(%rcx)
	movq	%r13,PCB_R13(%rcx)
	movq	%r14,PCB_R14(%rcx)
	movq	%r15,PCB_R15(%rcx)
	pushfq
	popq	PCB_RFLAGS(%rcx)

	/*
	 * If fpcurthread == NULL, then the npx h/w state is irrelevant and the
	 * state had better already be in the pcb.  This is true for forks
	 * but not for dumps (the old book-keeping with FP flags in the pcb
	 * always lost for dumps because the dump pcb has 0 flags).
	 *
	 * If fpcurthread != NULL, then we have to save the npx h/w state to
	 * fpcurthread's pcb and copy it to the requested pcb, or save to the
	 * requested pcb and reload.  Copying is easier because we would
	 * have to handle h/w bugs for reloading.  We used to lose the
	 * parent's npx state for forks by forgetting to reload.
	 */
	pushfq
	cli
	movq	PCPU(FPCURTHREAD),%rax
	testq	%rax,%rax
	je	1f

	pushq	%rcx
	pushq	%rax
	movq	TD_PCB(%rax),%rdi
	leaq	PCB_SAVEFPU(%rdi),%rdi
	call	npxsave
	popq	%rax
	popq	%rcx

	movq	$PCB_SAVEFPU_SIZE,%rdx	/* arg 3 */
	leaq	PCB_SAVEFPU(%rcx),%rsi	/* arg 2 */
	movq	%rax,%rdi		/* arg 1 */
	call	bcopy
1:
	popfq

	ret
