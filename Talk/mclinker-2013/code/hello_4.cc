          ...

  llvm::Value *helloWorld
      = builder.CreateGlobalStringPtr("hello world!\n");

  module->dump( );
}
