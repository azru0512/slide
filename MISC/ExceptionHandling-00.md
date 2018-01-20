<p align="center">
Copyright (c) 2018 陳韋任 (Chen Wei-Ren)<br><br>
<b>本文只描述 Unix 上對於 C++ 例外處理的實現。此文和 <a href=https://people.cs.nctu.edu.tw/~chenwj/dokuwiki/doku.php?id=exception_handling>Exception Handling</a> 互相搭配。</b>
</p>

# 例外處理概觀

我們先從底下一個簡單的例子，描述什麼是例外，以及例外如何被處理。

```c++
void foo() {
  throw 0;
}

int bar() {
  try {
    foo();
  } catch (...) {
    return -1;
  }

  return 0;
}
```

C++ 對於例外在語法上的支持，一是透過 ``throw`` 丟出例外，如上述的 ``foo`` 函式; 二是在 ``try`` block 內調用可能丟出例外的函式，並在 ``try`` block 之後的 ``catch`` block 是撰寫例外處理相關代碼。只有 ``try`` block 丟出例外時，``catch`` block 才有可能會被執行。

在 C++ 例外語法的背後，底層的例外處理流程是從 ``throw`` 丟出例外開始的。當例外丟出之後，我們會在調用棧上，以 callee 往 caller 的方法尋找能夠處理該例外的 ``catch`` block。一但找到相應的 ``catch`` block，我們會將暫存器和棧回復到 ``catch`` block 所在的棧框，再開始執行 ``catch`` block 內的代碼。

以上面的代碼為例。當 ``foo`` 丟出例外時，調用棧如底下所示:

```
                |           |
             |  |-----------|
             |  |           |
             |  |    bar    |
stack growth |  |           |
             |  |-----------|
             |  |           |
             |  |    foo    |
             v  |           |
                 -----------
```

``foo`` 沒有 ``catch`` block 可以處理例外，因此我們在調用棧上查看 ``foo`` 的 caller, ``bar``，是否有 ``catch`` block 可以處理 ``foo`` 丟出的例外。由於 ``bar`` 有 ``catch`` block 可以處理例外，我們便把暫存器和棧的狀態回朔至 ``bar`` 所在的棧框，再執行位於 ``bar`` 的 ``catch`` block。

```
      |            |
      |------------|
      |            |  ^
 bar  |    catch   |  |
      |            |  |
      |------------|  |
      |  prologue  |  | unwind direction
      |            |  |
 foo  |    throw   |  |
      |            |  |
      |  epilogue  |  |
       ------------
```

這裡稍微解釋一下什麼叫"把暫存器和棧的狀態回朔至 ``bar`` 所在的棧框"。函式一般會在其開頭和結尾有兩段代碼，分別稱為 prologue 和 epilogue。prologue 負責將 callee-saved 暫存器保存到棧上，epilogue 從棧上將 callee-saved 暫存器加以回復並返回至 caller。以上面的例子來看，當 ``foo`` 丟出例外時，epilogue 不會被執行到。我們必須透過其它方式回復 callee-saved 暫存器，這樣執行位在 ``bar`` 的 ``catch`` block 才不會發生問題。這個過程稱為 *unwind stack*。負責 *unwind stack* 的稱為 *unwinder*。

# 初探例外處理實現機制

由於例外本質上不常發生，不屬於正常程序執行的流程，我們希望例外處理的指令只有在例外發生時才會執行到，不影響正常程序執行的性能。[Itanium C++ ABI: Exception Handling](https://itanium-cxx-abi.github.io/cxx-abi/abi-eh.html) 這一規格透過查表，而非在正常程序流程插入檢測代碼，實現例外處理，因此被稱作 *zero-cost*。GCC 和 LLVM 基本都是實現該規格來支持例外處理。

Itanium C++ ABI: Exception Handling 定義了語言相關和語言無關的 ABI，分別為 [C++ ABI](https://itanium-cxx-abi.github.io/cxx-abi/abi-eh.html#cxx-abi) 和 [Base ABI](https://itanium-cxx-abi.github.io/cxx-abi/abi-eh.html#base-abi)。 GCC 的實現分別是 [libstdc++](https://github.com/gcc-mirror/gcc/tree/master/libstdc%2B%2B-v3) 和 [libgcc](https://github.com/gcc-mirror/gcc/tree/master/libgcc); LLVM 的實現是 [libc++](https://github.com/llvm-mirror/libcxx) 和 [libunwind](https://github.com/llvm-mirror/libunwind)。編譯器在例外處理中的角色，一是負責對 ``try`` 和 ``catch`` 生成 [C++ ABI](https://itanium-cxx-abi.github.io/cxx-abi/abi-eh.html#cxx-abi) 對應接口的調用; 二是負責生成表，供例外處理函式查詢。

以 GCC 對於 ``throw`` 的處理為例。底下大致描述了編譯器和底層彼此的關聯。

```
   C++    |             libstdc++            |                libgcc
          |                                  |
          |                                  |
  throw --|-----> __cxa_allocate_exceptions  |
          |  |                               |
          |  |                               |
          |  |                               |
          |  |                               |
          |   -------> __cxa_throw ----------|-------> _Unwind_RaiseExceptionn
          |                                  |
          |                                  |                   |
          |                                  |                   |
          |       __gxx_personality_v0 <-----|-------------------
          |                                  |
```

我們可以觀察丟出例外的 ``foo`` 匯編，稍加驗證一下 ``throw`` 是不是被編譯器生成對 ``__cxa_allocate_exceptions`` ([eh_alloc.c](https://github.com/gcc-mirror/gcc/blob/master/libstdc%2B%2B-v3/libsupc%2B%2B/eh_alloc.cc)) 和 ``__cxa_throw`` ([eh_throw.cc](https://github.com/gcc-mirror/gcc/blob/master/libstdc%2B%2B-v3/libsupc%2B%2B/eh_throw.cc)) 的調用。

``` asm
_Z3foov:
.LFB0:
        .cfi_startproc
        pushq   %rbp
        .cfi_def_cfa_offset 16
        .cfi_offset 6, -16
        movq    %rsp, %rbp
        .cfi_def_cfa_register 6
        movl    $4, %edi
        call    __cxa_allocate_exception@PLT ; allocate exception object
        movl    $0, (%rax)
        movl    $0, %edx
        leaq    _ZTIi(%rip), %rsi
        movq    %rax, %rdi
        call    __cxa_throw@PLT              ; initialize the object, call _Unwind_Raise_Exception
        .cfi_endproc
```

接著我們看 ``_Unwind_RaiseException`` ([unwind.inc](https://github.com/gcc-mirror/gcc/blob/master/libgcc/unwind.inc))。

``` c
_Unwind_Reason_Code LIBGCC2_UNWIND_ATTRIBUTE
_Unwind_RaiseException(struct _Unwind_Exception *exc)
{
  struct _Unwind_Context this_context, cur_context;
  _Unwind_Reason_Code code;
  unsigned long frames;

  /* Set up this_context to describe the current stack frame.  */
  uw_init_context (&this_context);
  cur_context = this_context;

  /* Phase 1: Search.  Unwind the stack, calling the personality routine
     with the _UA_SEARCH_PHASE flag set.  Do not modify the stack yet.  */
  while (1)
    {
      _Unwind_FrameState fs;

      /* Set up fs to describe the FDE for the caller of cur_context.  The
	 first time through the loop, that means __cxa_throw.  */
      code = uw_frame_state_for (&cur_context, &fs);

      if (code == _URC_END_OF_STACK)
	/* Hit end of stack with no handler found.  */
	return _URC_END_OF_STACK;

      if (code != _URC_NO_REASON)
	/* Some error encountered.  Usually the unwinder doesn't
	   diagnose these and merely crashes.  */
	return _URC_FATAL_PHASE1_ERROR;

      /* Unwind successful.  Run the personality routine, if any.  */
      if (fs.personality)
	{
	  code = (*fs.personality) (1, _UA_SEARCH_PHASE, exc->exception_class,
				    exc, &cur_context);
	  if (code == _URC_HANDLER_FOUND)
	    break;
	  else if (code != _URC_CONTINUE_UNWIND)
	    return _URC_FATAL_PHASE1_ERROR;
	}

      /* Update cur_context to describe the same frame as fs.  */
      uw_update_context (&cur_context, &fs);
    }

  /* Indicate to _Unwind_Resume and associated subroutines that this
     is not a forced unwind.  Further, note where we found a handler.  */
  exc->private_1 = 0;
  exc->private_2 = uw_identify_context (&cur_context);

  cur_context = this_context;
  code = _Unwind_RaiseException_Phase2 (exc, &cur_context, &frames);
  if (code != _URC_INSTALL_CONTEXT)
    return code;

  uw_install_context (&this_context, &cur_context, frames);
}
```

``_Unwind_RaiseException`` 內的 `while(1)` 迴圈基本上就是在調用棧上由 callee 往 caller 的方向查找包含可以處理當前例外的 ``catch`` block 所在的棧框，以我們的範例而言，就是指 ``bar``。`while(1)` 上的註解:

> /* Phase 1: Search.  Unwind the stack, calling the personality routine`
>      with the _UA_SEARCH_PHASE flag set.  Do not modify the stack yet.  */

說明這是第一階段，功能是搜尋。搜尋什麼呢？當然就是前面提到過的，包含可以處理當前例外的 ``catch`` block 所在的棧框，這裡稱為 handler。另外，既然有第一階段，是不是有第二階段？有的。如果 ``_Unwind_RaiseException`` 搜尋到 handler，最後會調用 ``_Unwind_RaiseException_Phase2`` ([unwind.inc](https://github.com/gcc-mirror/gcc/blob/master/libgcc/unwind.inc))。``_Unwind_RaiseException_Phase2`` 的最終任務是執行 handler，並在從丟出例外的棧框 (``foo``) 一路回溯到處理該例外的棧框 (``bar``) 的過程中，執行清理 (cleanup)，如銷毀物件。

如果 ``_Unwind_RaiseException`` 沒有搜尋到 handler，會返回到 ``__cxa_throw``，最後調用 ``std::terminate`` 終止程序的執行。這裡要注意的是，如果 ``_Unwind_RaiseException`` 搜尋到 handler，*不會*返回到 ``__cxa_throw``。[再探例外處理實現機制](#再探例外處理實現機制) 對這種情況會有進一步的描述。

``` c
extern "C" void
__cxxabiv1::__cxa_throw (void *obj, std::type_info *tinfo,
			 void (_GLIBCXX_CDTOR_CALLABI *dest) (void *))
{
  // ...

  _Unwind_RaiseException (&header->exc.unwindHeader);

  // Some sort of unwinding error.  Note that terminate is a handler.
  __cxa_begin_catch (&header->exc.unwindHeader);
  std::terminate ();
}

```

```
   C++    |             libstdc++            |                libgcc
          |                                  |
          |                                  |         _Unwind_RaiseException
          |                                  |
          |                                  |                   |
          |                                  |                   |
          |       __gxx_personality_v0 <-----|-------------------------------------
          |                                  |                                     |
          |                 |                |                                     |
          |                 |                |             Find handler?           |
          |                  ----------------|-------------------                  |
          |                                  |                   |                 |
          |                                  |            ----------------         |
          |                                  |         N |                |        |
          |            __cxa_throw <---------|-----------                 | Y      |
          |                                  |                            |        |
          |                 |                |                            v        |
          |                 |                |    
          |                 v                |                  _Unwind_RaiseException_Phase2
          |                                  |
          |           std::terminate         |
```

上圖總結了 ``_Unwind_RaiseException`` 到 ``_Unwind_RaiseException_Phase2`` 之間的流程。這裡可以注意到，搜尋和清理的任務基本上都是交由 ``__gxx_personality_v0`` ([eh_personality.cc](https://github.com/gcc-mirror/gcc/blob/master/libstdc%2B%2B-v3/libsupc%2B%2B/eh_personality.cc)) 完成。``__gxx_personality_v0`` 透過查找編譯器生成的表，得知目前棧框是否有可以處理當前例外的 ``catch`` block。

``` c
static _Unwind_Reason_Code
_Unwind_RaiseException_Phase2(struct _Unwind_Exception *exc,
			      struct _Unwind_Context *context,
			      unsigned long *frames_p)
{
  _Unwind_Reason_Code code;
  unsigned long frames = 1;

  while (1)
    {
      _Unwind_FrameState fs;
      int match_handler;

      code = uw_frame_state_for (context, &fs);

      /* Identify when we've reached the designated handler context.  */
      match_handler = (uw_identify_context (context) == exc->private_2
		       ? _UA_HANDLER_FRAME : 0);

      if (code != _URC_NO_REASON)
	/* Some error encountered.  Usually the unwinder doesn't
	   diagnose these and merely crashes.  */
	return _URC_FATAL_PHASE2_ERROR;

      /* Unwind successful.  Run the personality routine, if any.  */
      if (fs.personality)
	{
	  code = (*fs.personality) (1, _UA_CLEANUP_PHASE | match_handler,
				    exc->exception_class, exc, context);
	  if (code == _URC_INSTALL_CONTEXT)
	    break;
	  if (code != _URC_CONTINUE_UNWIND) 
	    return _URC_FATAL_PHASE2_ERROR;
	}

      /* Don't let us unwind past the handler context.  */
      gcc_assert (!match_handler);

      uw_update_context (context, &fs);
      frames++;
    }

  *frames_p = frames;
  return code;
}
```

`_Unwind_RaiseException_Phase2` 的 `while (1)` 和 `_Unwind_RaiseException_Phase1` 很相似。這裡要注意的是調用 `__gxx_personality_v0` 時，於 `_Unwind_RaiseException_Phase1` 和 `_Unwind_RaiseException_Phase2` 傳入的參數分別是 `_UA_SEARCH_PHASE` 和 `_UA_CLEANUP_PHASE`。`__gxx_personality_v0` 就是藉由這個參數得知當前是處於搜尋或是清理的階段。

# 再探例外處理實現機制

編譯器為例外處理，供 ``__gxx_personality_v0`` ([eh_personality.cc](https://github.com/gcc-mirror/gcc/blob/master/libstdc%2B%2B-v3/libsupc%2B%2B/eh_personality.cc)) 查詢所生成的表會被匯總成 LSDA (Language Specific Data Area)，數個 LSDA 又會被放在 ``.gcc_except_table`` 段。LSDA 的規格可以參考 [Exception Handling Tables](https://itanium-cxx-abi.github.io/cxx-abi/exceptions.pdf)。

```
   .gcc_except_table
   -----------------                 LSDA
  |      LSDA 0     | ---->  ---------------------
  |-----------------|       |       Header        |
  |      LSDA 1     |       |---------------------|
  |-----------------|       |   Call Site Table   |
  |       ...       |       |---------------------|
  |-----------------|       |    Action Table     |
  |      LSDA n     |       |---------------------|
   -----------------        |     Type Table      |
                             ---------------------
```

對於帶有 try-catch block 的函式，如 `bar`，編譯器會在其匯編代碼之後生成 ``.gcc_except_table`` 段。

`__gxx_personality_v0` 透過 `_Unwind_GetLanguageSpecificData` 取得 `.gcc_except_table` 的位址，並以 `_Unwind_GetIP` 取得丟出例外的位址，進行底下查表。

1. 查詢 [Call Site Table](#call-site-table), 可以得知丟出例外的位址是否有相應的 landing pad 和 action。landing pad 可以粗略的想成就是 ``catch`` block。
2. 於 [Action Table](#action-table) 透過 [Type Table](#type-table) 的索引取得 landing pad (``catch`` block) 所能處理例外的型別，並和當前例外的型別相比。如果相同，代表 landing pad (``catch`` block) 可以處理當前的例外。

``` c
PERSONALITY_FUNCTION (int version,
		      _Unwind_Action actions,
		      _Unwind_Exception_Class exception_class,
		      struct _Unwind_Exception *ue_header,
		      struct _Unwind_Context *context)
{
  language_specific_data = (const unsigned char *)
    _Unwind_GetLanguageSpecificData (context);

  // Parse the LSDA header.
  p = parse_lsda_header (context, language_specific_data, &info);
  ip = _Unwind_GetIP (context);

  // Search the call-site table for the action associated with this IP.
  while (p < info.action_table)
    {
      _Unwind_Ptr cs_start, cs_len, cs_lp;
      _uleb128_t cs_action;

      // Note that all call-site encodings are "absolute" displacements.
      p = read_encoded_value (0, info.call_site_encoding, p, &cs_start);
      p = read_encoded_value (0, info.call_site_encoding, p, &cs_len);
      p = read_encoded_value (0, info.call_site_encoding, p, &cs_lp);
      p = read_uleb128 (p, &cs_action);

      // The table is sorted, so if we've passed the ip, stop.
      if (ip < info.Start + cs_start)
	p = info.action_table;
      else if (ip < info.Start + cs_start + cs_len)
	{
	  if (cs_lp)
	    landing_pad = info.LPStart + cs_lp;
	  if (cs_action)
	    action_record = info.action_table + cs_action - 1;
	  goto found_something;
	}
    }
}
```

底下是 `__gxx_personality_v0` 透過 LSDA 找到 handler 之後的流程。

```
        C++      |           libstdc++         |                     libgcc
                 |                             |
 foo:            |                             |
   throw 0; -----|-------> __cxa_throw --------|-------------> _Unwind_RaiseException
                 |                             |        
                 |               --------------|--- uw_install_context -  |
 bar:            |              |              |           (2)          | |
                 |              | (3)          |                        | |
   catch (...) { | <------------               |                        | |
     return -1;  |                             |                        | v
   }             |                             |
 LSDA: <---------|--- __gxx_personality_v0 <---|-------------- _Unwind_RaiseException_Phase2
                 |             (1)             |
                 |                             |
```

1. 在找到 handler 之後，`__gxx_personality_v0` 透過底下接口 ([1.5 Context Management](https://itanium-cxx-abi.github.io/cxx-abi/abi-eh.html#base-context)) 設置 handler 的 context。
  * `_Unwind_SetGR`: 傳遞例外和例外型別給 landing pad。
  * `_Unwind_SetIP`: 設定欲執行 landing pad 所在位址。

``` c
  /* For targets with pointers smaller than the word size, we must extend the
     pointer, and this extension is target dependent.  */
  _Unwind_SetGR (context, __builtin_eh_return_data_regno (0),
		 __builtin_extend_pointer (ue_header));
  _Unwind_SetGR (context, __builtin_eh_return_data_regno (1),
		 handler_switch_value);
  _Unwind_SetIP (context, landing_pad);
  return _URC_INSTALL_CONTEXT;
}
```

2. `uw_install_context` ([unwind-dw2.c](https://github.com/gcc-mirror/gcc/blob/master/libgcc/unwind-dw2.c)) 調整棧指針，並將 `_Unwind_RaiseException` (`this_context`) 的返回位址設置成位於 `bar` 的 handler。
  * `cur_context` 為可以處理當前例外的棧框，即 `bar`。 
  * `this_context` 為當前的棧框，即 `_Unwind_RaiseException`。

``` c
  cur_context = this_context;
  code = _Unwind_RaiseException_Phase2 (exc, &cur_context, &frames);
  if (code != _URC_INSTALL_CONTEXT)
    return code;

  uw_install_context (&this_context, &cur_context, frames);
}
```

  * `CURRENT` 是當前的棧框，`TARGET` 是 handler 所在的棧框。`uw_install_context` 做的是調整棧指針，從 `CURRENT` 跳到位於 `TARGET` 的 handler。
  * [HexagonISelLowering.cpp](http://llvm.org/doxygen/HexagonISelLowering_8cpp_source.html) 和 [HexagonFrameLowering.cpp](https://github.com/llvm-mirror/llvm/blob/master/lib/Target/Hexagon/HexagonFrameLowering.cpp)。

``` c
/* Install TARGET into CURRENT so that we can return to it.  This is a
   macro because __builtin_eh_return must be invoked in the context of
   our caller.  FRAMES is a number of frames to be unwind.
   _Unwind_Frames_Extra is a macro to do additional work during unwinding
   if needed, for example shadow stack pointer adjustment for Intel CET
   technology.  */

#define uw_install_context(CURRENT, TARGET, FRAMES)			\
  do									\
    {									\
      long offset = uw_install_context_1 ((CURRENT), (TARGET));		\
      void *handler = uw_frob_return_addr ((CURRENT), (TARGET));	\
      _Unwind_DebugHook ((TARGET)->cfa, handler);			\
      _Unwind_Frames_Extra (FRAMES);					\
      __builtin_eh_return (offset, handler);				\
    }									\
  while (0)
```

3. 從 `_Unwind_RaiseException` 返回位於 `bar` 的 handler。調用棧如底下所示:

```
|                           |
|---------------------------|
|                           |
|             bar           | <--
|                           |    |
|---------------------------|    |
|                           |    |
|             foo           |    |
|                           |    |
|---------------------------|    |
|                           |    |
| __cxa_allocate_exceptions |    |
|                           |    |
|---------------------------|    |
|                           |    |
|   _Unwind_RaiseException  |    |
|                           | ---
 ---------------------------

```

# 三探例外處理實現機制

在[例外處理概觀](#例外處理概觀)有這樣一句話:

> 把暫存器和棧的狀態回朔至 bar 所在的棧框。

這部分的工作是透過 ``uw_frame_state_for`` ([unwind-dw2.c](https://github.com/gcc-mirror/gcc/blob/master/libgcc/unwind-dw2.c)) 和 ``uw_update_context`` ([unwind-dw2.c](https://github.com/gcc-mirror/gcc/blob/master/libgcc/unwind-dw2.c)) 這兩個函式完成。

``` c
  while (1)
    {
      _Unwind_FrameState fs;

      /* Set up fs to describe the FDE for the caller of cur_context.  The
	 first time through the loop, that means __cxa_throw.  */
      code = uw_frame_state_for (&cur_context, &fs);

      if (code == _URC_END_OF_STACK)
	/* Hit end of stack with no handler found.  */
	return _URC_END_OF_STACK;

      if (code != _URC_NO_REASON)
	/* Some error encountered.  Usually the unwinder doesn't
	   diagnose these and merely crashes.  */
	return _URC_FATAL_PHASE1_ERROR;

      /* Unwind successful.  Run the personality routine, if any.  */
      if (fs.personality)
	{
	  code = (*fs.personality) (1, _UA_SEARCH_PHASE, exc->exception_class,
				    exc, &cur_context);
	  if (code == _URC_HANDLER_FOUND)
	    break;
	  else if (code != _URC_CONTINUE_UNWIND)
	    return _URC_FATAL_PHASE1_ERROR;
	}

      /* Update cur_context to describe the same frame as fs.  */
      uw_update_context (&cur_context, &fs);
    }
```

```
   C++    |             libstdc++            |                libgcc
          |                                  |
          |            __cxa_throw ----------|-------> _Unwind_RaiseException
          |                                  |
          |                                  |                   |
          |                                  |                   v
          |                                  |
          |                                  |           uw_frame_state_for <--
          |                                  |                                 |
          |                                  |                   |             |
          |       __gxx_personality_v0 <-----|-------------------|             |
          |                                  |                   |             |
          |                                  |                   v             |
          |                                  |                                 |
          |                                  |            uw_update_context ---
          |                                  |
```

上面的代碼和流程圖可以清楚看到 ``uw_frame_state_for`` 和 ``uw_update_context`` 在 ``_Unwind_RaiseExceptionn`` 的位置。

這裡有幾個資料結構需要認識一下。

* ``_Unwind_Context`` 和 ``_Unwind_FrameState``。

  * ``uw_update_context`` 的註解。

    > /* CONTEXT describes the unwind state for a frame, and FS describes the FDE
    >    of its caller.  Update CONTEXT to refer to the caller as well.  Note
    >    that the args_size and lsda members are not updated here, but later in
    >    uw_frame_state_for.  */

    ``_Unwind_Context`` 指的是當前棧框狀態，``_Unwind_FrameState`` 指的是當前棧框其 caller 的狀態。

* [FDE](#fde) 和 [CIE](#cie)

  * ``uw_frame_state_for`` 的註解。

    > /* Given the _Unwind_Context CONTEXT for a stack frame, look up the FDE for
    >    its caller and decode it into FS.  This function also sets the
    >    args_size and lsda members of CONTEXT, as they are really information
    >    about the caller's frame.  */

    編譯器會為編譯單元中的每一個函式生成 FDE (Frame Description Entry)，數個 FDE 共同的部分抽取出來作為 CIE (Common Information Entry)。例外處理過程中，將 ``foo`` 的 prologue 所保存的 callee-saved 暫存器回復，而不經由執行 ``foo`` 的 epilogue，就是透過執行 CIE 和 FDE 中的指令達成。

``uw_frame_state_for`` 的工作是將傳入的 ``_Unwind_Context`` 其 caller 更新至 ``_Unwind_FrameState``，也就是 *frame state for* ``_Unwind_Context``。基本作法是將用當前棧框的返回地址 (``context->ra``) 查找到 caller 所屬的 FDE (同時一併帶出 CIE)，執行 CIE 和 FDE 中的指令 (``execute_cfa_program``)。

``uw_update_context`` 的工作是將當前的 ``_Unwind_Context``，藉由 ``_Unwind_FrameState`` 更新至 caller 的 ``_Unwind_Context``，也就是 *update context* ``_Unwind_Context``。

# 編譯器後端支持

GCC 請見 [18.9.2 Exception Handling Support](https://gcc.gnu.org/onlinedocs/gccint/Exception-Handling.html)。
- `EH_RETURN_DATA_REGNO (N)`
- `EH_RETURN_STACKADJ_RTX`
- `EH_RETURN_HANDLER_RTX`

LLVM 請見 [Exception Handling support on the target](https://llvm.org/docs/ExceptionHandling.html#exception-handling-support-on-the-target)。

# 附錄

## .gcc_except_table

``.gcc_except_table`` 包含 ``__gxx_personality_v0`` 所需的 LSDA。這一部分可以參考 [Exception Handling Tables](https://itanium-cxx-abi.github.io/cxx-abi/exceptions.pdf) 和 [.gcc_except_table](https://www.airs.com/blog/archives/464)。

### LSDA Header

```
           LSDA
   ---------------------
  |       Header        | ---->  ----------------------
  |---------------------|       |   LPStart encoding   |
  |   Call Site Table   |       |----------------------|
  |---------------------|       |  LPStart (optional)  |
  |    Action Table     |       |----------------------|
  |---------------------|       |     TType format     |
  |     Type Table      |       |----------------------|
   ---------------------        |   TType base offset  |
                                |----------------------|
                                |   Call Site format   |
                                |----------------------|
                                | Call Site table size |
                                 ----------------------
```

- LPStart encoding: 下一個欄位，LPStart 的編碼。
- LPStart: landping pad 的基址，預設為函式起始位址。此為可選欄位。
- TType format: Type Table entry 的編碼。
- TType base offset: Type Table 與此欄位的 offset。
- Call Site format: Call Site Table entry 的編碼。
- Call Site table size: Call Site Table 長度。

關於 encoding 和 format 的值，請見 [dwarf2.h](https://github.com/gcc-mirror/gcc/blob/master/include/dwarf2.h)。

``` asm
.LFE1:
        .globl  __gxx_personality_v0
        .section        .gcc_except_table,"a",@progbits
        .align 4
.LLSDA1:
        .byte   0xff    # @LPStart format (omit)
        .byte   0x9b    # @TType format (indirect pcrel sdata4)
        .uleb128 .LLSDATT1-.LLSDATTD1   # @TType base offset
.LLSDATTD1:
        .byte   0x1     # call-site format (uleb128)
        .uleb128 .LLSDACSE1-.LLSDACSB1  # Call-site table length
```

### Call Site Table

```
           LSDA
   ---------------------
  |       Header        |
  |---------------------|
  |   Call Site Table   | ---->  ----------------------
  |---------------------|       |  Call Site Record 0  | ---->  ----------------------
  |    Action Table     |       |----------------------|       |  call site position  |
  |---------------------|       |  Call Site Record 1  |       |----------------------|
  |     Type Table      |       |----------------------|       |   call site length   |
   ---------------------        |          ...         |       |----------------------|
                                |----------------------|       | landing pad position |
                                |  Call Site Record n  |       |----------------------|
                                 ----------------------        |  first action index  |
                                                                ----------------------
```

- call site positin: 對應指令區段其起始位址相對於 LPStart 的 offset。
- call site length: 對應指令區段的長度。
- landing pad position: 相應 landing pad 其起始位址相對於 LPStart 的 offset。若無相應的 landing pad，此處為 0。
- first action index: 相應 action 於 Action Table 的偏移 (實際偏移須減去 1)。若無相應的 action，此處為 0。

``` c
	  if (cs_action)
	    action_record = info.action_table + cs_action - 1;
```

``` asm
.LLSDACSB1:
        .uleb128 .LEHB0-.LFB1   # region 0 start
        .uleb128 .LEHE0-.LEHB0  # length
        .uleb128 .L5-.LFB1      # landing pad
        .uleb128 0x1    # action
        .uleb128 .LEHB1-.LFB1   # region 1 start
        .uleb128 .LEHE1-.LEHB1  # length
        .uleb128 0      # landing pad
        .uleb128 0      # action
```

### Action Table

```
           LSDA
   ---------------------
  |       Header        |
  |---------------------|
  |   Call Site Table   |
  |---------------------|
  |    Action Table     | ---->  ------------
  |---------------------|       |  action 0  | ---->  -----------------------
  |     Type Table      |       |------------|       |      type filter      |
   ---------------------        |  action 1  |       |-----------------------|
                                |------------|       | offset to next action |
                                |    ...     |        -----------------------
                                |------------|
                                |  action n  |
                                 ------------
```

- type filter: 若為 0，代表為 cleanup。若為正數，代表 `catch` 所能處理的例外型別於 [Type Table](#type-table) 的索引 (實際索引須乘上 -1)。
- offset to next action: 下一個要執行的 action 於 Action Table 的 offset。若無，此處為 0。

``` c
      while (1)
	{
	  p = action_record;
	  p = read_sleb128 (p, &ar_filter);
	  read_sleb128 (p, &ar_disp);

	  if (ar_filter == 0)
	    {
	      // Zero filter values are cleanups.
	      saw_cleanup = true;
	    }
	  else if (ar_filter > 0)
	    {
	      // Positive filter values are handlers.
	      catch_type = get_ttype_entry (&info, ar_filter);

	      // Null catch type is a catch-all handler; we can catch foreign
	      // exceptions with this.  Otherwise we must match types.
	      if (! catch_type
		  || (throw_type
		      && get_adjusted_ptr (catch_type, throw_type,
					   &thrown_ptr)))
		{
		  saw_handler = true;
		  break;
		}
	    }
	  else
	    {
	      // Negative filter values are exception specifications.
	      // ??? How do foreign exceptions fit in?  As far as I can
	      // see we can't match because there's no __cxa_exception
	      // object to stuff bits in for __cxa_call_unexpected to use.
	      // Allow them iff the exception spec is non-empty.  I.e.
	      // a throw() specification results in __unexpected.
	      if ((throw_type
		   && !(actions & _UA_FORCE_UNWIND)
		   && !foreign_exception)
		  ? ! check_exception_spec (&info, throw_type, thrown_ptr,
					    ar_filter)
		  : empty_exception_spec (&info, ar_filter))
		{
		  saw_handler = true;
		  break;
		}
	    }

	  if (ar_disp == 0)
	    break;
	  action_record = p + ar_disp;
	}

      if (saw_handler)
	{
	  handler_switch_value = ar_filter;
	  found_type = found_handler;
	}
      else
	found_type = (saw_cleanup ? found_cleanup : found_nothing);
    }
```

``` asm
.LLSDACSE1:
        .byte   0x1     # Action record table
        .byte   0
```

### Type Table

```asm
        .align 4
        .long   0

.LLSDATT1:
```

## .eh_frame

`.eh_frame` 和 `.debug_frame` 相似，前者用於例外處理，後者用於 GDB。兩者基本上都是透過編譯器生成 `.cfi` 匯編指示符 ([7.10 CFI directives](https://sourceware.org/binutils/docs/as/CFI-directives.html))，再由匯編器生成相應的段。

`.debug_frame` 可以參考:
* [Decoding .debug_frame information from DWARF-2](http://ucla.jamesyxu.com/?p=231)
* [DWARF Debugging Information Format 6.4 Call Frame Information](http://dwarfstd.org/doc/dwarf-2.0.0.pdf#page=61)
* [DWARF Debugging Information Format Appendix 5](http://dwarfstd.org/doc/dwarf-2.0.0.pdf#page=101)

`.eh_frame` 可以參考:
* [.eh_frame_hdr](https://www.airs.com/blog/archives/462)
* [.eh_frame](https://www.airs.com/blog/archives/460)
* [10.6. Exception Frames](https://refspecs.linuxfoundation.org/LSB_5.0.0/LSB-Core-generic/LSB-Core-generic/ehframechpt.html)

這裡簡單介紹 [DWARF Debugging Information Format 6.4 Call Frame Information](http://dwarfstd.org/doc/dwarf-2.0.0.pdf#page=61) 提及的概念，並以 [DWARF Debugging Information Format Appendix 5](http://dwarfstd.org/doc/dwarf-2.0.0.pdf#page=101) 的例子加以解釋。

```
high  -------------- <---- old R7 (CFA)
     |      R1      |
     |--------------| 8
     |    old R6    |
     |--------------| 4
     |      R4      |
      -------------- <---- new R7/R6
 low
```

``` asm
       ;; start prologue
foo    sub   R7, R7, <fsize>      ; Allocate frame
foo+4  store R1, R7, (<fsize>-4)  ; Save the return address
foo+8  store R6, R7, (<fsize>-8)  ; Save R6
foo+12 add   R6, R7, 0            ; R6 is now the Frame ptr
foo+16 store R4, R6, (<fsize>-12) ; Save a preserve reg.
       ;; This subroutine does not change R5
       ...
       ;; Start epilogue (R7 has been returned to entry value)
foo+64 load  R4, R6, (<fsize>-12) ; Restore R4
foo+68 load  R6, R7, (<fsize>-8)  ; Restore R6
foo+72 load  R1, R7, (<fsize>-4)  ; Restore return address
foo+76 add   R7, R7, <fsize>      ; Deallocate frame
foo+80 jump  R                    ; Return
foo+84
```

```
Loc    CFA        R0 R1 R2 R3 R4  R5 R6 R7 R8
foo    [R7]+0     s  u  u  u  s   s  s  s  r1 # 尚未執行第一條指令。caller 調用 foo 時，R8 (PC) 被存在 R1。
foo+4  [R7]+fsize s  u  u  u  s   s  s  s  r1 # 執行完 foo    指令。CFA 為當前 R7 + fsize。
foo+8  [R7]+fsize s  u  u  u  s   s  s  s  c4 # 執行完 foo+4  指令。R1 存在 CFA - 4。
foo+12 [R7]+fsize s  u  u  u  s   s  c8 s  c4 # 執行完 foo+8  指令。R6 存在 CFA - 8。
foo+16 [R6]+fsize s  u  u  u  s   s  c8 s  c4 # 執行完 foo+12 指令。當前棧底由 R7 改為 R6。CFA 為當前 R6 + fsize。
foo+20 [R6]+fsize s  u  u  u  c12 s  c8 s  c4 # 執行完 foo+16 指令。R4 存在 CFA - 12。
foo+64 [R6]+fsize s  u  u  u  c12 s  c8 s  c4 # 此時棧頂 R7 已回復到 R6 所在位置。
foo+68 [R6]+fsize s  u  u  u  s   s  c8 s  c4 # 執行完 foo+64 指令。R4 回復至調用前的狀態。
foo+72 [R7]+fsize s  u  u  u  s   s  s  s  c4 # 執行完 foo+68 指令。R6 回復至 old R6。當前棧底由 R6 改為 R7。
foo+76 [R7]+fsize s  u  u  u  s   s  s  s  r1 # 執行完 foo+72 指令。R1 回復至調用前的狀態。
foo+80 [R7]+0     s  u  u  u  s   s  s  s  r1 # 執行完 foo+74 指令。CFA 為當前 R7。
```

```
cie+13 DW_CFA_def_cfa (7, 0)  ; CFA = [R7]+0
cie+16 DW_CFA_same_value (0)  ; R0 not modified (=0)
cie+18 DW_CFA_undefined (1)   ; R1 scratch
cie+20 DW_CFA_undefined (2)   ; R2 scratch
cie+22 DW_CFA_undefined (3)   ; R3 scratch
cie+24 DW_CFA_same_value (4)  ; R4 preserve
cie+26 DW_CFA_same_value (5)  ; R5 preserve
cie+28 DW_CFA_same_value (6)  ; R6 preserve
cie+30 DW_CFA_same_value (7)  ; R7 preserve
cie+32 DW_CFA_register (8, 1) ; R8 is in R1
```

```
fde+16 DW_CFA_advance_loc(1)            ; foo+4
fde+17 DW_CFA_def_cfa_offset(<fsize>/4) ; CFA = [R7] + <fsize>/4 (4)
fde+19 DW_CFA_advance_loc(1)            ; foo+8
fde+20 DW_CFA_offset(8,1)               ; R8 = CFA - 1 (4)
fde+22 DW_CFA_advance_loc(1)            ; foo+12
fde+23 DW_CFA_offset(6,2)               ; R6 = CFA - 2 (4)
fde+25 DW_CFA_advance_loc(1)            ; foo+16
fde+26 DW_CFA_def_cfa_register(6)       ; CFA = [R6] + <fsize>/4 (4)
fde+28 DW_CFA_advance_loc(1)            ; foo+20
fde+29 DW_CFA_offset(4,3)               ; R4 = CFA - 3 (4)
fde+31 DW_CFA_advance_loc(11)           ; foo+64
fde+32 DW_CFA_restore(4)                ; R4 回復至調用前的狀態。 
fde+33 DW_CFA_advance_loc(1)            ; foo+68
fde+34 DW_CFA_restore(6)                ; R6 回復至調用前的狀態。
fde+35 DW_CFA_def_cfa_register(7)       ; R6 回復至 old R6。當前棧底由 R6 改為 R7。
fde+37 DW_CFA_advance_loc(1)            ; foo+68
fde+38 DW_CFA_restore(8)                ; R8 回復至調用前的狀態。
fde+39 DW_CFA_advance_loc(1)            ; foo+72
fde+40 DW_CFA_def_cfa_offset(0)         ; CFA = [R7]+0
```

### CIE

```
00000034 000000000000001c 00000000 CIE
  Version:               1
  Augmentation:          "zPLR"
  Code alignment factor: 1
  Data alignment factor: -8
  Return address column: 16
  Augmentation data:     9b b9 ff ff ff 1b 1b

  DW_CFA_def_cfa: r7 (rsp) ofs 8
  DW_CFA_offset: r16 (rip) at cfa-8
  DW_CFA_nop
  DW_CFA_nop
```

* Version: 值為 1。
* Augmentation: 為一 NULL 結尾的字串，用於描述 CIE 和與其相關聯的 FDE 額外屬性。
  * z: Augmentation data 需有值。其解釋依據 Augmentation 剩餘其它字串。
  * P: 只有在 z 為首字符時才會出現。Personality routine 的位址。
  * L: 只有在 z 為首字符時才會出現。LSDA 的位址。
  * R: 只有在 z 為首字符時才會出現。
* Code alignment factor: DW_CFA_advance_loc 乘上的倍數。
* Data alignment factor: DW_CFA_def_cfa_offset 乘上的倍數。
* Return address column: 存放返回地址的暫存器號。
* Augmentation data: 只有在 Augmentation 包含 z 字符時才有值。其解釋依據 Augmentation。

### FDE

```
00000054 0000000000000024 00000024 FDE cie=00000034 pc=0000000000000028..0000000000000080
  Augmentation data:     9b ff ff ff

  DW_CFA_advance_loc: 1 to 0000000000000029
  DW_CFA_def_cfa_offset: 16
  DW_CFA_offset: r6 (rbp) at cfa-16
  DW_CFA_advance_loc: 3 to 000000000000002c
  DW_CFA_def_cfa_register: r6 (rbp)
  DW_CFA_advance_loc: 5 to 0000000000000031
  DW_CFA_offset: r3 (rbx) at cfa-24
  DW_CFA_advance_loc1: 78 to 000000000000007f
  DW_CFA_def_cfa: r7 (rsp) ofs 8
  DW_CFA_nop
  DW_CFA_nop
  DW_CFA_nop
```

# 遺留問題

- [[llvm-dev] Exception handling support for a target](http://lists.llvm.org/pipermail/llvm-dev/2018-January/120405.html)
- [[llvm-dev] What is __builtin_dwarf_cfa()?](http://lists.llvm.org/pipermail/llvm-dev/2018-March/121773.html)

# 參考

- [Dwarf2 Exception Handler HOWTO](https://gcc.gnu.org/wiki/Dwarf2EHNewbiesHowto)
- [Itanium C++ ABI: Exception Handling](https://itanium-cxx-abi.github.io/cxx-abi/abi-eh.html)
- [C++ exception handling internals](https://monoinfinito.wordpress.com/series/exception-handling-in-c/)
- [淺談C++例外處理 (前篇)](http://luse.blogspot.tw/2009/05/c.html)
- [淺談C++例外處理 (中篇)](http://luse.blogspot.tw/2009/10/c.html)
- [淺談C++例外處理 (後篇)](http://luse.blogspot.tw/2010/01/c.html)
