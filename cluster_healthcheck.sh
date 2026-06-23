#!/usr/bin/env bash

# This script runs some basic checks of the software osdataproc
# should have installed when creating your cluster and reports
# the versions of the main components

# NOTE: This script needs to be run on the master node, not the
# provisioning machine and can be found in /opt/osdataproc on the
# master node

set +e

PASS=0
FAIL=0

check() {
    if [ $1 -eq 0 ]; then
        echo "[PASS] $2"
        PASS=$((PASS+1))
    else
        echo "[FAIL] $2"
        FAIL=$((FAIL+1))
    fi
}

echo "=================================================="
echo "CLUSTER HEALTH CHECK"
echo "=================================================="
date
hostname

echo
echo "=================================================="
echo "VERSIONS"
echo "=================================================="

echo
echo "Java:"
java -version 2>&1 | head -1

echo
echo "Python:"
python3 --version

echo
echo "Hadoop:"
hadoop version 2>/dev/null | head -2

echo
echo "Spark:"
spark-submit --version 2>&1 | grep version | head -1

echo
echo "Hail:"
python3 - <<'PY'
try:
    import hail as hl
    print(hl.__version__)
except Exception as e:
    print("NOT AVAILABLE:", e)
PY

echo
echo "=================================================="
echo "YARN CHECK"
echo "=================================================="

yarn node -list > /tmp/yarn_nodes.txt 2>&1
check $? "YARN reachable"

cat /tmp/yarn_nodes.txt

WORKERS=$(grep RUNNING /tmp/yarn_nodes.txt | wc -l)
echo
echo "Workers detected: $WORKERS"

echo
echo "=================================================="
echo "HDFS CHECK"
echo "=================================================="

hdfs dfsadmin -report > /tmp/hdfs_report.txt 2>&1
check $? "HDFS reachable"

grep -E "Live datanodes|Dead datanodes" /tmp/hdfs_report.txt

LIVE_NODES=$(grep -A1 "Live datanodes" /tmp/hdfs_report.txt | head -1)

echo
echo "=================================================="
echo "HDFS WRITE/READ TEST"
echo "=================================================="

TESTDIR="/tmp/cluster_health_$$"

echo "hello cluster" > /tmp/healthcheck.txt

hdfs dfs -mkdir -p "$TESTDIR" >/dev/null 2>&1
hdfs dfs -put -f /tmp/healthcheck.txt "$TESTDIR/" >/dev/null 2>&1

check $? "HDFS write"

hdfs dfs -cat "$TESTDIR/healthcheck.txt" >/tmp/healthcheck.out 2>&1

grep -q "hello cluster" /tmp/healthcheck.out
check $? "HDFS read"

hdfs dfs -rm -r -f "$TESTDIR" >/dev/null 2>&1

echo
echo "=================================================="
echo "MAPREDUCE TEST"
echo "=================================================="

JAR=$(find ${HADOOP_HOME:-/opt/hadoop} \
      -name "hadoop-mapreduce-examples-*.jar" \
      ! -name "*sources*" \
      ! -name "*test*" \
      ! -name "*javadoc*" \
      | head -1)

if [ -n "$JAR" ]; then

    timeout 300 \
        hadoop jar "$JAR" pi 2 100 >/tmp/mapreduce_test.log 2>&1

    check $? "MapReduce example job"

    grep "Estimated value of Pi" /tmp/mapreduce_test.log

else
    echo "[WARN] Example jar not found"
fi

echo
echo "=================================================="
echo "SPARK TEST"
echo "=================================================="

cat >/tmp/spark_test.py <<'PY'
from pyspark.sql import SparkSession

spark = SparkSession.builder.appName("healthcheck").getOrCreate()

sc = spark.sparkContext

print("Spark version:", sc.version)
print("Default parallelism:", sc.defaultParallelism)

rdd = sc.parallelize(range(100000), 20)

print("Count:", rdd.count())

spark.stop()
PY

spark-submit /tmp/spark_test.py >/tmp/spark_test.log 2>&1
check $? "Spark job"

grep -E "Spark version|Default parallelism|Count:" /tmp/spark_test.log

echo
echo "=================================================="
echo "HAIL TEST"
echo "=================================================="

cat >/tmp/hail_test.py <<'PY'
import hail as hl

hl.init()

ht = hl.utils.range_table(100000)

result = ht.aggregate(
    hl.agg.sum(ht.idx)
)

print("Hail version:", hl.__version__)
print("Result:", result)

hl.stop()
PY

python3 /tmp/hail_test.py >/tmp/hail_test.log 2>&1
check $? "Hail distributed aggregation"

grep -E "Hail version|Result:" /tmp/hail_test.log

echo
echo "=================================================="
echo "SUMMARY"
echo "=================================================="

echo "PASS: $PASS"
echo "FAIL: $FAIL"

if [ "$FAIL" -eq 0 ]; then
    echo
    echo "CLUSTER STATUS: HEALTHY"
    exit 0
else
    echo
    echo "CLUSTER STATUS: ISSUES DETECTED"
    exit 1
fi

