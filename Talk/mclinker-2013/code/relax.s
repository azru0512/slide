	.file	"relax.c"
	.text
	.globl	foo
	.align	16, 0x90
	.type	foo,@function
foo:                                    # @foo
# BB#0:
	pushq	%rbp
	movq	%rsp, %rbp
	pushq	%r15
	pushq	%r14
	pushq	%rbx
	pushq	%rax
	movl	%edi, %ebx
	callq	bar
	movl	%eax, %r14d
	imull	$17, %ebx, %r15d
	movl	%ebx, %edi
	callq	bar
	cmpl	%r14d, %r15d
	jle	.LBB0_2
	.fill 124, 1, 0x90 # nop
# BB#1:
	addl	%r15d, %eax
	jmp	.LBB0_3
.LBB0_2:
	imull	%ebx, %eax
.LBB0_3:
	addq	$8, %rsp
	popq	%rbx
	popq	%r14
	popq	%r15
	popq	%rbp
	ret
.Ltmp0:
	.size	foo, .Ltmp0-foo


	.section	".note.GNU-stack","",@progbits
