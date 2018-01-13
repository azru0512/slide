extern int bar(int);

int foo(int num) {
  int t1 = num * 17;
  if (t1 > bar(num)) {
    return t1 + bar(num);
  }
  return num * bar(num);
}
