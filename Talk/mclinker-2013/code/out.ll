; ModuleID = 'out.bc'
target datalayout = "e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v64:64:64-v128:128:128-a0:0:64-s0:64:64-f80:128:128-n8:16:32:64-S128"
target triple = "amd64-portbld-freebsd8.3"

define zeroext i1 @_Z9predicatebb(i1 zeroext %x, i1 zeroext %y) nounwind {
  %1 = alloca i8, align 1
  %2 = alloca i8, align 1
  %z = alloca i8, align 1
  %3 = zext i1 %x to i8
  store i8 %3, i8* %1, align 1
  %4 = zext i1 %y to i8
  store i8 %4, i8* %2, align 1
  %5 = load i8* %2, align 1
  %6 = trunc i8 %5 to i1
  br i1 %6, label %10, label %7

; <label>:7                                       ; preds = %0
  %8 = load i8* %1, align 1
  %9 = trunc i8 %8 to i1
  br label %10

; <label>:10                                      ; preds = %7, %0
  %11 = phi i1 [ true, %0 ], [ %9, %7 ]
  %12 = zext i1 %11 to i8
  store i8 %12, i8* %z, align 1
  %13 = load i8* %z, align 1
  %14 = trunc i8 %13 to i1
  ret i1 %14
}

define i32 @_Z3foov() nounwind {
  ret i32 1
}
