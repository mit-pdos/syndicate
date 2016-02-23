# Syndicate

Syndicate is an application that allows the multiplexing of several
distributed master-slave applications onto a single cluster of machines.
It is primarily used for the final lab in [MIT
6.824](https://pdos.csail.mit.edu/6.824/), but may have use-cases
outside of this deployment.

A Syndicate cluster consists of a single *manager* machine, and any
number of cluster *volunteers*. *Users* submit *jobs* in the form of
source code tarballs, which should contain a `Makefile` with (at least)
two targets: `master` and `slave`. Along with the job, the user
specifies the number of machines to use for the job. When that number of
volunteers become available, the manager reserves them, and distributes
the user's source to each volunteer. One volunteer is elected the
*master*, and `make master` is executed on that machine in a chroot
rooted in the user's source directory. The remaining reserved volunteers
are marked as *slaves*, and the manager executes `make
MASTER=<master_ip> slave` on each one in another chroot. The volunteers
are freed when all masters and slaves terminate.

## Benchmarking and testing

The intended use for Syndicate is to benchmark student submissions. To
that end, the source for a *client* may be given to the Syndicate
manager when it is started. This source is distributed to each volunteer
when it initially registers. When a new job is scheduled, a configurable
number of clients are also launched (the number of volunteers allocated
for a job is padded to accommodate the clients). Specifically

```
make MASTER=<master_ip> SLAVES<slave1_ip,slave2_ip,...> client
```

is run on each client volunteer, again chrooted inside the source
directory for that client.

To allow the clients to stress-test jobs, the manager exposes a number
of special RPCs listed in the table below. Note that a client may only
name the IPs belonging to volunteers allocated for that job.

   Method               | Function
------------------------|---------
`Kill(ip)`              | Kills any processes spawned by this job on the indicate volunteer
`Revive(ip, with_disk)` | Revives this job on the given volunteer, optionally without its disk (i.e., with its chroot emptied)
`Disconnect(ip)`        | Disconnects the given volunteer from all master and slave volunteers
`Reconnect(ip)`         | Reconnects the given volunteer to all master and slave volunteers
`Finish()`              | Indicates that this client has finished its work

**Note**: when the Syndicate is running with clients, the volunteers
will be freed when all the clients have called `Finish()`. This means
that the master and slaves may be terminated during computation.

## Freeing volunteers

Volunteers are assumed to be running from an ephemeral VM disk image, so
that a reboot will clear all state on the machine. When a volunteer
starts up, it should immediately register with the manager without
requiring any user input.
