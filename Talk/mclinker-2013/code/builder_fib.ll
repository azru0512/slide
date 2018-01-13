; ModuleID = 'fib.c'

define i32 @fib(i32 %x) nounwind uwtable {
entry:
            ...
  %cmp = icmp sle i32 %0, 2
  br i1 %cmp, label %if.then, label %if.else

if.then:                    ; preds = %entry
  store i32 1, i32* %sum, align 4
  br label %if.end

if.else:                    ; preds = %entry
            ...
  %call2 = call i32 @fib(i32 %sub1)
  %add = add nsw i32 %call, %call2
  store i32 %add, i32* %sum, align 4
  br label %if.end

if.end:                     ; preds = %if.else, %if.then
  %3 = load i32* %sum, align 4
  ret i32 %3
}
