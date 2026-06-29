#!/usr/bin/env python3

import sys
import platform
from pyspark.sql import SparkSession
from pyspark.sql import functions as F

print("=" * 70)
print("DRIVER")
print("=" * 70)
print("Python executable :", sys.executable)
print("Python version    :", platform.python_version())

spark = (
    SparkSession.builder
    .config("spark.ui.showConsoleProgress", "false")
    .config("spark.eventLog.enabled", "false")
    .appName("OSDataProc Cluster Test")
    .getOrCreate()
)
spark.sparkContext.setLogLevel("ERROR")

sc = spark.sparkContext

print("\nSpark version     :", spark.version)
print("Master            :", sc.master)
print("Default parallelism:", sc.defaultParallelism)
print("spark.pythonExec  :", sc.pythonExec)

print("\n" + "=" * 70)
print("TEST 1 - Basic RDD")
print("=" * 70)

rdd = sc.parallelize(range(100000), 8)
assert rdd.count() == 100000
assert rdd.sum() == sum(range(100000))
print("PASS")

print("\n" + "=" * 70)
print("TEST 2 - map/filter/reduce")
print("=" * 70)

r = (
    sc.parallelize(range(1000), 4)
      .map(lambda x: x * 2)
      .filter(lambda x: x % 3 == 0)
      .sum()
)

expected = sum(i * 2 for i in range(1000) if (i * 2) % 3 == 0)

assert r == expected
print("PASS")

print("\n" + "=" * 70)
print("TEST 3 - DataFrame")
print("=" * 70)

df = spark.range(100000)

assert df.count() == 100000
assert df.agg(F.sum("id")).first()[0] == sum(range(100000))

print("PASS")

print("\n" + "=" * 70)
print("TEST 4 - GroupBy")
print("=" * 70)

df = spark.range(1000).withColumn("group", F.col("id") % 10)

result = (
    df.groupBy("group")
      .agg(F.count("*").alias("count"))
      .orderBy("group")
      .collect()
)

assert len(result) == 10
assert all(r["count"] == 100 for r in result)

print("PASS")

print("\n" + "=" * 70)
print("TEST 5 - Cache")
print("=" * 70)

df = spark.range(1000000).cache()

assert df.count() == 1000000
assert df.filter("id < 100").count() == 100

print("PASS")

print("\n" + "=" * 70)
print("TEST 6 - Broadcast Variable")
print("=" * 70)

broadcast = sc.broadcast({i: i * i for i in range(100)})

result = (
    sc.parallelize(range(100))
      .map(lambda x: broadcast.value[x])
      .sum()
)

expected = sum(i * i for i in range(100))

assert result == expected

broadcast.unpersist()

print("PASS")

print("\n" + "=" * 70)
print("TEST 7 - Executor Python")
print("=" * 70)

versions = (
    sc.parallelize(range(sc.defaultParallelism), sc.defaultParallelism)
      .map(lambda _: (sys.executable, platform.python_version()))
      .distinct()
      .collect()
)

print("Executor versions:")
for exe, ver in versions:
    print(" ", exe, ver)

assert len(versions) == 1
assert versions[0][1] == platform.python_version()

print("PASS")

print("\n" + "=" * 70)
print("TEST 8 - Shuffle")
print("=" * 70)

rdd = (
    sc.parallelize(range(100000), 8)
      .map(lambda x: (x % 100, 1))
      .reduceByKey(lambda a, b: a + b)
)

result = dict(rdd.collect())

assert len(result) == 100
assert all(v == 1000 for v in result.values())

print("PASS")

print("\n" + "=" * 70)
print("TEST 9 - SQL")
print("=" * 70)

df = spark.range(1000)
df.createOrReplaceTempView("numbers")

row = spark.sql("""
SELECT
    COUNT(*) AS c,
    SUM(id) AS s,
    AVG(id) AS a
FROM numbers
""").first()

assert row.c == 1000
assert row.s == sum(range(1000))
assert abs(row.a - 499.5) < 1e-9

print("PASS")

print("\n" + "=" * 70)
print("TEST 10 - Partitioning")
print("=" * 70)

rdd = sc.parallelize(range(100000), 16)

assert rdd.getNumPartitions() == 16

sizes = rdd.glom().map(len).collect()

print("Partition sizes:", sizes)

assert sum(sizes) == 100000

print("PASS")

print("\n" + "=" * 70)
print("ALL TESTS PASSED")
print("=" * 70)

spark.stop()
