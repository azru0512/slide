define i32 @bar(i32 %x) nounwind {
  %1 = alloca i32, align 4
  store i32 %x, i32* %1, align 4
  %2 = load i32* %1, align 4
  %3 = icmp ne i32 %2, 0
  br i1 %3, label %4, label %7

; <label>:4                                       ; preds = %0
  %5 = call i32 @foo()
  %6 = add nsw i32 %5, 1
  br label %9

; <label>:7                                       ; preds = %0
  %8 = call i32 @baz()
  br label %9

; <label>:9                                       ; preds = %7, %4
  %10 = phi i32 [ %6, %4 ], [ %8, %7 ]
  ret i32 %10
}
