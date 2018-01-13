          ...

  builder.CreateCall(putsFunc, helloWorld);
  builder.CreateRetVoid();

  module->dump();
}
