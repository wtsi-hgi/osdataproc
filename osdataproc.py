#!/usr/bin/env python3

import argparse
import os
import subprocess
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.request import urlopen

import volumes
import yaml


def _download_with_progress(url: str, dest_path: str) -> None:
    """Download a file showing a simple progress bar and speed."""
    print(f"Starting download: {url}")
    try:
        with urlopen(url) as response:
            total_size_header = response.headers.get("Content-Length")
            total_size = int(total_size_header) if total_size_header else None
            chunk_size = 1024 * 1024  # 1 MiB
            bytes_read = 0
            start_time = time.time()
            last_update = 0.0
            with open(dest_path, "wb") as out_f:
                while True:
                    chunk = response.read(chunk_size)
                    if not chunk:
                        break
                    out_f.write(chunk)
                    bytes_read += len(chunk)

                    now = time.time()
                    # Throttle UI updates to ~10 per second
                    if now - last_update >= 0.1:
                        elapsed = max(now - start_time, 1e-6)
                        speed = bytes_read / elapsed  # bytes/sec
                        if total_size:
                            percent = (bytes_read / total_size) * 100.0
                            progress = f"{percent:6.2f}%"
                            total_mb = total_size / (1024 * 1024)
                            read_mb = bytes_read / (1024 * 1024)
                            line = f"  {progress}  {read_mb:,.1f}/{total_mb:,.1f} MiB  {speed / 1_000_000:,.2f} MB/s"
                        else:
                            read_mb = bytes_read / (1024 * 1024)
                            line = (
                                f"  {read_mb:,.1f} MiB  {speed / 1_000_000:,.2f} MB/s"
                            )
                        print("\r" + line, end="", flush=True)
                        last_update = now

            # Final line
            if total_size:
                total_mb = total_size / (1024 * 1024)
                print(f"\r  100.00%  {total_mb:,.1f}/{total_mb:,.1f} MiB  done       ")
            else:
                read_mb = bytes_read / (1024 * 1024)
                print(f"\r  {read_mb:,.1f} MiB  done                      ")
            print(f"Saved to: {dest_path}")
    except (URLError, HTTPError) as e:
        print(f"Warning: could not download {url}: {e}")


def ensure_pre_downloads(config):
    """
    Download Hadoop and Spark artifacts to a local cache before the pipeline runs.
    This allows Ansible to use local files instead of downloading on the master.
    """

    downloads_dir = os.path.expanduser(
        config.get("downloads_dir", "/tmp/osdataproc-cache")
    )
    os.makedirs(downloads_dir, exist_ok=True)

    hadoop_version = config.get("hadoop_version")
    spark_version = config.get("spark_version")

    hadoop_mirror = config.get(
        "hadoop_mirror", "https://mirrors.sonic.net/mirrors/apache/hadoop/common"
    )
    spark_mirror = config.get(
        "spark_mirror", "https://mirrors.sonic.net/mirrors/apache/spark"
    )

    planned_downloads = []
    if hadoop_version:
        hadoop_filename = f"hadoop-{hadoop_version}.tar.gz"
        hadoop_url = f"{hadoop_mirror}/hadoop-{hadoop_version}/{hadoop_filename}"
        planned_downloads.append(
            (hadoop_url, os.path.join(downloads_dir, hadoop_filename))
        )
    if spark_version:
        spark_filename = f"spark-{spark_version}-bin-without-hadoop.tgz"
        spark_url = f"{spark_mirror}/spark-{spark_version}/{spark_filename}"
        planned_downloads.append(
            (spark_url, os.path.join(downloads_dir, spark_filename))
        )

    for url, dest in planned_downloads:
        try:
            if os.path.exists(dest) and os.path.getsize(dest) > 0:
                print(f"Using cached artifact: {dest}")
                continue
        except OSError:
            # Will attempt to download
            pass
        _download_with_progress(url, dest)


def create(args):
    # Ensure required artifacts are available locally before provisioning
    ensure_pre_downloads(args)
    if args["nfs_volume"] is not None and args["volume_size"] is None:
        # find ID of specified volume
        args["nfs_volume"] = volumes.get_volume_id(args["nfs_volume"], to_create=False)
    elif args["nfs_volume"] is not None and args["volume_size"] is not None:
        # create a volume and return its ID if unique name
        if volumes.get_volume_id(args["nfs_volume"], to_create=True) is None:
            args["nfs_volume"] = volumes.create_volume(
                args["nfs_volume"], args["volume_size"]
            )
        else:
            sys.exit("Please use a unique volume name.")
    act(args, "apply")


def destroy(args):
    volumes_to_destroy = volumes.get_attached_volumes(
        os.environ["OS_USERNAME"] + "-" + args["cluster-name"] + "-master"
    )
    act(args, "destroy")
    if args["destroy-volumes"] and volumes_to_destroy is not None:
        # destroy volumes attached to instance
        volumes.destroy_volumes(volumes_to_destroy)


def update(args):
    act(args, "update")


def reboot(args):
    act(args, "reboot")


def act(args, command):
    if "OS_USERNAME" not in os.environ:
        sys.exit("openrc.sh must be sourced")
    osdataproc_home = os.path.dirname(os.path.realpath(__file__))
    run_args = get_args(args, command)
    subprocess.run([f"{osdataproc_home}/run", "init"])
    # Ensure the CLI-provided public key is injected into vars.yml for Ansible
    # This mirrors/augments the injection performed in the run script and ensures
    # correctness even when vars.yml already exists from a previous run.
    try:
        tf_state_dir = os.environ.get(
            "TF_STATE_DIR", os.path.join(os.getcwd(), "terraform-state")
        )
        os.makedirs(tf_state_dir, exist_ok=True)
        vars_path = os.path.join(tf_state_dir, "vars.yml")
        data = {}
        try:
            with open(vars_path, "r") as f:
                data = yaml.safe_load(f) or {}
        except FileNotFoundError:
            # vars.yml will be created by run/init copy if missing; we still write our override
            data = {}
        osd = data.get("osdataproc") or {}
        if args.get("public_key"):
            osd["public_key"] = args["public_key"]
            data["osdataproc"] = osd
            with open(vars_path, "w") as f:
                yaml.safe_dump(data, f, default_flow_style=False, sort_keys=False)
    except Exception as e:
        print(f"Warning: could not inject public_key into vars.yml: {e}")
    subprocess.run(run_args)


def get_args(args, command):
    osdataproc_home = os.path.dirname(os.path.realpath(__file__))
    run_args = [f"{osdataproc_home}/run", command]

    # FIXME The order in which the keys are iterated through matters to
    # the downstream "run" script, which uses positional arguments.
    # Changed loop to explicit items to match script's expectations.
    run_args += [
        str(args["cluster-name"]),
        str(args["num_workers"]),
        str(args["public_key"]),
        str(args["flavour"]),
        str(args["network_name"]),
        str(args["lustre_network"]),
        str(args["image_name"]),
        str(args["nfs_volume"]),
        str(args["volume_size"]),
        str(args["device_name"]),
        str(args["floating_ip"]),
    ]

    return run_args


def cli():
    """osdataproc"""
    parser = argparse.ArgumentParser(
        description="CLI tool to manage a Spark and Hadoop cluster"
    )
    subparsers = parser.add_subparsers()

    parser_create = subparsers.add_parser("create", help="create a Spark cluster")

    parser_create.add_argument("cluster-name", help="name of the cluster to create")
    parser_create.add_argument(
        "-n", "--num-workers", type=int, help="number of worker nodes"
    )
    parser_create.add_argument("-p", "--public-key", help="path to public key file")
    parser_create.add_argument(
        "-f", "--flavour", "--flavor", help="OpenStack flavour to use"
    )
    parser_create.add_argument("--network-name", help="OpenStack network to use")
    parser_create.add_argument(
        "--lustre-network", help="OpenStack Secure Lustre network to use"
    )
    parser_create.add_argument(
        "-i", "--image-name", help="OpenStack image to use - Ubuntu only"
    )
    parser_create.add_argument(
        "-v",
        "--nfs-volume",
        help="Name or ID of an nfs volume to attach to the cluster",
    )

    volume_create = parser_create.add_mutually_exclusive_group()
    volume_create.add_argument(
        "-s", "--volume-size", help="Size of OpenStack volume to create"
    )
    volume_create.add_argument(
        "-d", "--device-name", help="Device mountpoint name of volume - see NFS.md"
    )

    parser_create.add_argument(
        "--floating-ip",
        help="OpenStack floating IP to associate to the master node - will automatically create one if not specified",
    )
    parser_create.set_defaults(func=create)

    parser_destroy = subparsers.add_parser("destroy", help="destroy a Spark cluster")
    parser_destroy.add_argument("cluster-name", help="name of the cluster to destroy")
    parser_destroy.add_argument(
        "-d",
        "--destroy-volumes",
        dest="destroy-volumes",
        action="store_true",
        help="also destroy volumes attached to cluster",
    )
    parser_destroy.set_defaults(func=destroy)

    parser_reboot = subparsers.add_parser(
        "reboot",
        help="reboot all worker nodes of a cluster, e.g. to pick up mount point changes",
    )
    parser_reboot.add_argument("cluster-name", help="name of the cluster to reboot")
    parser_reboot.set_defaults(func=reboot)

    args = parser.parse_args()

    osdataproc_home = os.path.dirname(os.path.realpath(__file__))
    with open(f"{osdataproc_home}/vars.yml", "r") as stream:
        defaults = yaml.safe_load(stream)

    # Build overrides from CLI where provided (CLI should take precedence)
    cli_overrides = {k: v for k, v in vars(args).items() if v is not None}
    # Map argparse names to vars.yml keys where they differ
    if "cluster_name" in cli_overrides:
        cli_overrides["cluster-name"] = cli_overrides.pop("cluster_name")
    if "flavor" in cli_overrides and "flavour" not in cli_overrides:
        # Normalise American spelling if ever present
        cli_overrides["flavour"] = cli_overrides.pop("flavor")

    # Start from defaults and apply CLI overrides last (priority)
    merged = dict(defaults["osdataproc"])
    merged.update(cli_overrides)
    for key in [
        "hadoop_version",
        "spark_version",
        "hadoop_mirror",
        "spark_mirror",
        "downloads_dir",
    ]:
        if key in defaults:
            merged[key] = defaults[key]

    args.func(merged)


if __name__ == "__main__":
    cli()
