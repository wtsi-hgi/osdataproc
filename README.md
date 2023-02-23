# osdataproc

osdataproc is a command-line tool for creating an OpenStack cluster with
[Apache Spark][spark] and [Apache Hadoop][hadoop] configured. It comes
with [JupyterLab][jupyter] and [Hail][hail], a genomic data analysis
library built on Spark installed, as well as [Netdata][netdata] for
monitoring.

### Setup

1. Create a Python virtual environment. For example:

   ```bash
   python3 -m venv env
   ```

2. Download [Terraform](https://terraform.io) (1.2, or higher) and
   unzip it into a location on your path, e.g. into your venv. Make sure
   to download the appropriate version for your operating system and
   architecture.

   ```bash
   wget https://releases.hashicorp.com/terraform/1.3.9/terraform_1.3.9_linux_amd64.zip
   unzip terraform_1.3.9_linux_amd64.zip -d env/bin/
   ```

3. Source the environment, clone this repository and install the
   requirements into the virtual environment:

   ```bash
   source env/bin/activate
   git clone https://github.com/wtsi-hgi/osdataproc.git
   cd osdataproc
   pip install -e .
   ```

4. Make sure you have created an SSH keypair with `ssh-keygen` if you
   have not done so before. The default options are OK. Read the notes
   below if your private key has a passphrase.

5. Download your OpenStack project's `openrc.sh` file. You can find the
   specific file for your project at Project > API Access, and then
   Download OpenStack RC File > OpenStack RC File on the right.

6. Source your `openrc.sh` file:

   ```bash
   source <project-name>-openrc.sh
   ```

You can then run the `osdataproc` command as shown in the examples,
below. `osdataproc --help`, or `osdataproc create --help`, etc. will
show all possible arguments.

Once run, it will ask you for a password. This is for access to the web
interfaces, including Jupyter Lab. It is also the password for an
encrypted NFS volume (see the [NFS documentation][nfs]). When you first
access your cluster via a browser you will be asked for said password.

### Example Usage

#### Create a Cluster

```
osdataproc create [--num-workers]    <Number of desired worker nodes>
                  [--public-key]     <Path to public key file>
                  [--flavour]        <OpenStack flavour to use>
                  [--network-name]   <OpenStack network to use>
                  [--lustre-network] <OpenStack Lustre provider network to use>
                  [--image-name]     <OpenStack image to use - Ubuntu images only>
                  [--nfs-volume]     <Name/ID of volume to attach or create as NFS shared volume>
                  [--volume-size]    <Size of OpenStack volume to create>
                  [--device-name]    <Device mountpoint name of volume>
                  [--floating-ip]    <OpenStack floating IP to associate to master node - will automatically create one if not specified>
                  <cluster_name>
```

NOTE: Ensure that the image used has python3.8 as the default version of python. The focal images should work.

`osdataproc create` will output the public IP of your master node when
the node has been created. You can SSH into this using the public key
provided:

```bash
ssh ubuntu@<public_ip>
```

Note that it will take a few minutes for the configuration to complete.
The following services can then be accessed from your browser:

| Service           | URL                             |
| :---------------- | :------------------------------ |
| Jupyter Lab       | `https://<public_ip>/jupyter`   |
| Spark             | `https://<public_ip>/spark`     |
| Spark History     | `https://<public_ip>/sparkhist` |
| HDFS              | `https://<public_ip>/hdfs`      |
| YARN              | `https://<public_ip>/yarn`      |
| MapReduce History | `https://<public_ip>/mapreduce` |
| Netdata Metrics   | `https://<public_ip>/netdata`   |

##### Attaching a Volume

You can attach a volume as an NFS share to your cluster creating either
a new volume, or attaching an existing volume. This will mount the
volume on the `data` directory and mount the `data` directory of your
master node to all of the worker nodes as a shared volume over NFS.

See the [NFS documentation][nfs] for details and creation options.

##### Lustre Support

For Lustre support, you must provide the name of the Lustre provider
network that exists in your tenant and an image configured to mount
Lustre from this network. For Sanger users, please check with ISG for
the details.

#### Destroy a Cluster

```
osdataproc destroy <cluster_name>
```

You will be prompted to type 'yes' if you are happy with printed destroy plan.

### Configuration Options

There is a [vars.yml][vars] file where default options for creating the
cluster can be saved, as well as Spark and Hadoop configuration items
tuned. Additional packages and Python modules to install on the cluster
can also be specified here.

### Troubleshooting Notes

* Please check the version of jinja2, make sure it is 3.0.3, otherwise you may have the error message as below.

  ```bash
  [WARNING]: Skipping plugin (/lib/python3.9/site-packages/ansible/plugins/filter/mathstuff.py) as it seems to be invalid: cannot import name
  'environmentfilter' from 'jinja2.filters' (/lib/python3.9/site-packages/jinja2/filters.py)
  ```

* For hail 0.2.88/spark 3.1.2 modify the following lines in the cluster's 
  `/opt/spark/conf/spark-defaults.conf` file
  ```bash
  spark.driver.extraClassPath      /home/ubuntu/venv/lib/python3.8/site-packages/hail/backend/hail-all-spark.jar
  spark.executor.extraClassPath    /home/ubuntu/venv/lib/python3.8/site-packages/hail/backend/hail-all-spark.jar
  spark.jars                       /home/ubuntu/venv/lib/python3.8/site-packages/hail/backend/hail-all-spark.jar
  ```

* Your cluster name should never contain underscore characters; valid
  choices are alphanumeric characters and dashes.

* If your private key has a passphrase, Ansible will not be able to
  connect to the created instances unless you add your key to
  `ssh-agent` first:

  ```bash
  eval $(ssh-agent)
  ssh-add
  ```

* You can check the provisioning status of the worker nodes via the
  master node and checking `/var/log/user_data.log`. For example:

  ```bash
  ssh -J ubuntu@<public-ip> \
      ubuntu@<user>-<cluster_name>-worker-<index> \
      tail -f /var/log/user_data.log
  ```

* `osdataproc` is configured to use Kryo serialization for use with Hail
  for up to 10x faster data serialization. However, not all
  `Serializable` types are supported and so it may be necessary to
  change `$SPARK_HOME/conf/spark-defaults.conf` by commenting out or
  removing the `spark.serializer` configuration option. This can also be
  removed by default in [vars.yml][vars] when creating a cluster.

* For Sanger users, check the appropriate FCE capacity dashboard under
  the [Sanger metrics][metrics].

* If `spark-submit` is not on PATH (`spark-submit: command not found`), activate the venv
    ```bash
    source /home/ubuntu/venv/bin/activate
    ```

* If running `spark-submit` you get the following error
    ```bash
    TypeError: 'JavaPackage' object is not callable
    ```
    check that `SPARK_HOME` is set to `/opt/spark`  
    ```bash
    export SPARK_HOME=/opt/spark
    ```

### Contributing and Editing

You can contribute by submitting pull requests to this repository. If
you create a fork you will need to update the `REPO` and `BRANCH`
variables in `terraform/user-data.sh.tpl` to the new repository location
for the changes you make to be reflected in the created cluster.

### To Do

* [ ] Refactor/enhance Python CLI
  * [ ] Move from `openrc.sh` to `clouds.yaml`
  * [ ] Incorporate `run` script into `osdataproc` Python CLI
  * [ ] Allow setting of password by environment variable
  * [ ] Allow multiple public SSH keys
  * [ ] Allow setting of DNS name servers
  * [ ] Use exit codes productively if Terraform/Ansible fail
  * [ ] Machine-readable output to communicate status
  * [ ] Allow non-interactive destruction
  * [ ] Correct distribution to recognise multiple Python modules
* [ ] Refactor Ansible playbooks
  * [ ] Update to JupyterLab 3
* [ ] Resize functionality (larger flavour/more nodes)
* [ ] Support for other Linux distributions

<!-- References -->
[hadoop]:  https://hadoop.apache.org
[hail]:    https://hail.is
[jupyter]: https://jupyter.org
[metrics]: https://metrics.internal.sanger.ac.uk
[netdata]: https://netdata.cloud
[nfs]:     NFS.md
[spark]:   https://spark.apache.org
[vars]:    vars.yml
