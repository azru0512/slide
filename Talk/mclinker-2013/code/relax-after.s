	.file	"relax.c"
	.text
	.globl	foo
	.align	16, 0x90
	.type	foo,@function
foo:                                    # @foo
# BB#0:
	pushq	%rbp
	movq	%rsp, %rbp
	pushq	%r14
	pushq	%rbx
	movl	%edi, %ebx
	imull	$17, %ebx, %r14d
	callq	bar
	cmpl	%eax, %r14d
	jle	.LBB0_2
# BB#1:
	#APP
	.fill 124, 1, 0x90 # nop
	#NO_APP
	movl	%ebx, %edi
	callq	bar
	addl	%r14d, %eax
	jmp	.LBB0_3
.LBB0_2:
	movl	%ebx, %edi
	callq	bar
	imull	%ebx, %eax
.LBB0_3:
	popq	%rbx
	popq	%r14
	popq	%rbp
	ret
.Ltmp0:
	.size	foo, .Ltmp0-foo


	.section	".note.GNU-stack","",@progbits
