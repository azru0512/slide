	.file	"fib.ll"
	.text
	.globl	fib
	.align	16, 0x90
	.type	fib,@function
fib:                                    # @fib
	.cfi_startproc
# BB#0:                                 # %entry
	pushq	%rbx
.Ltmp2:
	.cfi_def_cfa_offset 16
	subq	$16, %rsp
.Ltmp3:
	.cfi_def_cfa_offset 32
.Ltmp4:
	.cfi_offset %rbx, -16
	movl	%edi, 8(%rsp)
	cmpl	$2, %edi
	jg	.LBB0_2
# BB#1:                                 # %if.then
	movl	$1, 12(%rsp)
	jmp	.LBB0_3
.LBB0_2:                                # %if.end
	movl	8(%rsp), %edi
	decl	%edi
	callq	fib
	movl	%eax, %ebx
	movl	8(%rsp), %edi
	addl	$-2, %edi
	callq	fib
	addl	%ebx, %eax
	movl	%eax, 12(%rsp)
.LBB0_3:                                # %return
	movl	12(%rsp), %eax
	addq	$16, %rsp
	popq	%rbx
	ret
.Ltmp5:
	.size	fib, .Ltmp5-fib
	.cfi_endproc


	.section	".note.GNU-stack","",@progbits
