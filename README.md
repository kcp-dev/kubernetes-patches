# kcp-kubernetes-patches

Patch series for [kcp](https://github.com/kcp-dev/kcp) modifications to [kubernetes/kubernetes](https://github.com/kubernetes/kubernetes).

The patches in `patches/` are maintained as `git format-patch` output and are applied with `git am`.

## Developing

For this process to be idempotent in the kubernetes local clone, we have setup tags and branches to
be tied to remotes. When editing these scripts, please make sure to always use `<remote>/<branch>`
or `<remote>/<tag>` to address them. Avoid using any dynamic markers (e.g. HEAD) or simple
branch/tag names. For the kubernetes clone, the remotes are called `kubernetes` (upstream),
`kcp-dev` (our forks), and `origin` (fork of the user of this guide).

## The Rebase process

Follow the subsequent steps in order to complete the full rebase:

### Setting up repositories, branches, tags and remotes

Clone this repository, fill out the `.env` file and run the setup script:

```bash
git clone https://github.com/kcp-dev/kubernetes-patches
cd kubernetes-patches
# edit .env
./hack/setup.bash both
```

This will clone or update the repositories and make feature branches in
the kubernetes and the kcp clones.

The script is non-destructive, meaning it will checkout a new branch off
of the base branch with every call, adding a number to the templated
branch with every iteration.

That means its always possible to start over without loosing previous
work. If only kube or only kcp needs to be reset run `./hack/setup.bash
kube` and `./hack/setup.bash kcp` respectively.

The `kubernetes` and `kcp` directories are gitignored.

> [!NOTE]
> Using submodules instead of gitignoring the directories would also be
> an option, however for the moment this approach is simpler and
> sufficient.

If you have not already, create forks for [kcp-dev/kubernetes](https://github.com/kcp-dev/kubernetes) and [kcp-dev/kcp](https://github.com/kcp-dev/kcp).

Then point the `origin` remote of both clones to your forks:

```bash
export KUBERNETES_FORK_REMOTE=<your-kubernetes-fork-url>
export KCP_FORK_REMOTE=<your-kcp-fork-url>
./hack/setup-remotes.bash
```

!! After this stage, please do not make any changes to branch names, tags, or remotes, as the scripts
strictly rely on them !!

### Setting up go.work

After that run build the `go.work` file:

```bash
./hack/build-gowork.bash
```

This builds a functioning `go.work` based on the modules in both repositories.

### Regenerate patches

Since changes can be made upstream in between rebases, it is important to update the patch files first before attempting the rebase:
Note: This will show a bunch of diffs replacing 00000000000 with hashes. This is expected and will be cleaned up later. Do not commit any of these patch changes yet!

```bash
./hack/format-kube-patches.bash "$OLD_KUBE_1_TAG"
```

## Updating "soft" forks in kcp

First the soft forks must be updated.  Some modules in the staging
directories in the kcp repository contain modified copies of upstream
files. These are dependencies used both in kcp and the kubernetes fork.

Use the `bump-soft.bash` script to bump and commit the kube dependencies
in the modules containing soft forks.

```bash
./hack/bump-soft.bash
```

You may run into messages like this:

```text
go: github.com/kcp-dev/client-go/kubernetes/fake imports
	k8s.io/client-go/kubernetes/typed/scheduling/v1alpha1: module k8s.io/client-go@latest found (v0.36.0), but does not contain package k8s.io/client-go/kubernetes/typed/scheduling/v1alpha1
go: github.com/kcp-dev/client-go/kubernetes/typed/autoscaling/v2beta1/fake imports
	k8s.io/client-go/applyconfigurations/autoscaling/v2beta1: module k8s.io/client-go@latest found (v0.36.0), but does not contain package k8s.io/client-go/applyconfigurations/autoscaling/v2beta1
go: github.com/kcp-dev/client-go/kubernetes/typed/autoscaling/v2beta2/fake imports
	k8s.io/client-go/applyconfigurations/autoscaling/v2beta2: module k8s.io/client-go@latest found (v0.36.0), but does not contain package k8s.io/client-go/applyconfigurations/autoscaling/v2beta2
go: github.com/kcp-dev/client-go/kubernetes/typed/scheduling/v1alpha1/fake imports
	k8s.io/client-go/applyconfigurations/scheduling/v1alpha1: module k8s.io/client-go@latest found (v0.36.0), but does not contain package k8s.io/client-go/applyconfigurations/scheduling/v1alpha1
```

This happens when upstream removes APIs that are still references. These
issues will be fixed when updating the generated code so they can be
ignored at this step.

<!-- TODO: let the script dynamically update k8s deps instead of hardcoding  -->

Afterwards each of the soft forks needs to be updated and reviewed.

### apimachinery

apimachinery contains modified copies of upstream files.

To update the copies use a three way git merge.

#### reflector/reflector.go

```bash
git -C kubernetes show kubernetes/v${OLD_KUBE_1_TAG}:staging/src/k8s.io/client-go/tools/cache/reflector.go \
    > "$PATCHES_ROOT/kcp/staging/src/github.com/kcp-dev/apimachinery/third_party/reflector/reflector_base.go"
git -C kubernetes show kubernetes/v${NEW_KUBE_1_TAG}:staging/src/k8s.io/client-go/tools/cache/reflector.go \
    > "$PATCHES_ROOT/kcp/staging/src/github.com/kcp-dev/apimachinery/third_party/reflector/reflector_upstream.go"
git -C kcp merge-file staging/src/github.com/kcp-dev/apimachinery/third_party/reflector/reflector.go \
    "$PATCHES_ROOT/kcp/staging/src/github.com/kcp-dev/apimachinery/third_party/reflector/reflector_base.go" \
    "$PATCHES_ROOT/kcp/staging/src/github.com/kcp-dev/apimachinery/third_party/reflector/reflector_upstream.go"
```

#### reflector/controller.go

> [!NOTE]
> controller.go is a trimmed fork. After applying the patch, check the header comment in the file
> to see if anything in the documented surface area has changed. If the patch applied anything beyond
> this as new lines to the bottom of the file, you will need to manually remove those!

```bash
git -C kubernetes show kubernetes/v${OLD_KUBE_1_TAG}:staging/src/k8s.io/client-go/tools/cache/controller.go \
    > "$PATCHES_ROOT/kcp/staging/src/github.com/kcp-dev/apimachinery/third_party/reflector/controller_base.go"
git -C kubernetes show kubernetes/v${NEW_KUBE_1_TAG}:staging/src/k8s.io/client-go/tools/cache/controller.go \
    > "$PATCHES_ROOT/kcp/staging/src/github.com/kcp-dev/apimachinery/third_party/reflector/controller_upstream.go"
git -C kcp merge-file staging/src/github.com/kcp-dev/apimachinery/third_party/reflector/controller.go \
    "$PATCHES_ROOT/kcp/staging/src/github.com/kcp-dev/apimachinery/third_party/reflector/controller_base.go" \
    "$PATCHES_ROOT/kcp/staging/src/github.com/kcp-dev/apimachinery/third_party/reflector/controller_upstream.go"
```

Review the changes and fix any merge conflicts. After deleting the `_base.go` and `_upstream.go` files `go vet` can be used to validate that the code would at least build.

```bash
go vet -C kcp ./staging/src/github.com/kcp-dev/apimachinery/third_party/reflector/
```

#### shared informer

> [!NOTE]
> shared_informer.go is a mixed fork. After applying the patch, check the header comment in the file
> to see if anything in the documented surface area has changed.

```bash
git -C kubernetes show kubernetes/v${OLD_KUBE_1_TAG}:staging/src/k8s.io/client-go/tools/cache/shared_informer.go \
    > "$PATCHES_ROOT/kcp/staging/src/github.com/kcp-dev/apimachinery/third_party/informers/shared_informer_base.go"
git -C kubernetes show kubernetes/v${NEW_KUBE_1_TAG}:staging/src/k8s.io/client-go/tools/cache/shared_informer.go \
    > "$PATCHES_ROOT/kcp/staging/src/github.com/kcp-dev/apimachinery/third_party/informers/shared_informer_upstream.go"
git -C kcp merge-file staging/src/github.com/kcp-dev/apimachinery/third_party/informers/shared_informer.go \
    "$PATCHES_ROOT/kcp/staging/src/github.com/kcp-dev/apimachinery/third_party/informers/shared_informer_base.go" \
    "$PATCHES_ROOT/kcp/staging/src/github.com/kcp-dev/apimachinery/third_party/informers/shared_informer_upstream.go"
```

Review the changes and fix any merge conflicts. After deleting the `_base.go` and `_upstream.go` files `go vet` can be used to validate that the code would at least build.

```bash
go vet -C kcp ./staging/src/github.com/kcp-dev/apimachinery/third_party/informers/
```

### code-generator

Manually review upstream to check for any changes to these generators in the
kubernetes repository. If there is

```bash
git -C kubernetes diff kubernetes/v${OLD_KUBE_1_TAG}...kubernetes/v${NEW_KUBE_1_TAG} -- staging/src/k8s.io/code-generator
```

Once there are no changes required run the code generator and commit
that as a standalone commit:

```bash
make -C kcp code-generator-codegen
```

### client-go

Run the code generator:

```bash
make -C kcp client-go-codegen
```

And commit.

`client-go` has a helper script `populate-copies.sh` - cd into the
staging directory and run it:

```bash
cd kcp/staging/src/github.com/kcp-dev/client-go/
./hack/populate-copies.sh
```

This will copy files originally copied from upstream over the local
copies. Review the resulting changes and ensure upstream modifications
are addressed. If the changes are only related to ClusterPath injections, you can safely `git checkout`
that file. If there are new files or any changes made, make sure they reflect the multicluster compatibility.

Commit the changes (if there are relevant ones).

## Updating kubernetes fork

Now the patches are applied to the kubernetes fork.

The patches are maintained in the `patches/` directory and are applied
using `git-am`.

> [!NOTE]
> At any point `git am --abort` can be run to stop any reconciliation,
> remove all commits applied to the branch until that point and restore
> the previous base branch.

```bash
cd kubernetes
git am --3way ../patches/*.patch
```

When a patch fails to apply, git will stop and report the conflict:

```text
Applying: UPSTREAM: <carry>: ...
error: patch failed: ...
```

Resolve the conflict in the affected files, stage the changes and run
`git am --continue`. *Do not* run `git commit` - that will create a new
commit instead of updating the patch commit.

Repeat until all patches are applied.

> [!NOTE]
> TODO: add scripts automating some of the finalizing steps mentioned here:
> <https://docs.kcp.io/kcp/main/contributing/guides/rebasing-kubernetes/#rebase-process>

Specifically check that `staging/src/k8s.io/apiserver/pkg/clientsethack/adapter.go` satisfies `kubernetes.Interface`.

Now the vendor directories and codegen for kube must be updated - be
sure that this has the `GOWORK` set so the kube fork uses the updated
local copies:

```bash
export GOWORK="$(realpath go.work)"

./hack/pin-local-replace.bash

cd kubernetes
git add . && git commit -m 'CARRY: <drop>: Add kcp dependencies'

GOWORK= ./hack/update-vendor.sh

git add . && git commit -m 'CARRY: <drop>: vendor'

GOWORK= ./hack/update-codegen.sh

git add . && git commit -m 'CARRY: <drop>: codegen'

```

## Updating kcp

Go into kcp, ensure `GOWORK` is set, update `k8s.io/kubernetes` to the
targeted tag and run `go work sync` to update the go.mod/go.sum files.
Then run the code generation:

```bash
export GOWORK="$(realpath go.work)"

cd kcp
./hack/update-codegen-clients.sh
./hack/gen-patch-defaultrestmapper.sh
```

> [!NOTE]
> There's the codegen recipe and that will have to be run later when
> making the pull requests for the changes.

<!-- TODO just skip go mod download when GOROOT is set -->

And commit the generated code:

```bash
git add . && git commit -m "codegen"
```

Now run the tests in kcp to see if any breakages occur:

```bash
unset GOWORK

make fix-lint

make test

make test-e2e

make test-e2e-sharded-minimal
```

## PRs

### apimachinery, code-generator and client-go

Changes to apimachinery, code-generator and client-go need to be PRed first so we can build a staging
version of these components. For this a helper script extracts these changes onto a new branch and squashes
them into 3 distinct commits:

> [!NOTE]
> The publishing bot only accepts full commits which are able to pass a specific `go mod tidy` gate,
> therefore we need to squash them together.

```bash
./hack/build-staging-branch.bash
```

Afterwards either follow the scripts directions to push the branch and create a PR or do it manually
using your tooling of choice.

Subsequently send the PR to a maintainer; It is expected that CI for the PR is failing. The maintainer
then will:
    1. Review your changes, but not merge them!
    2. Update the `rebase-staging` branch to point to the latest main
    3. Cherry-pick the changes from your PR onto `rebase-staging`

This triggers the publishing bot to publish this branch to our staging repositories.

### Update kubernetes fork

Now drop the previous drop commits with the local replaces and update
the kcp deps:

```bash
cd kubernetes/
GOWORK= ./hack/pin-dependency.sh github.com/kcp-dev/logicalcluster/v3 v3.0.5
GOWORK= ./hack/pin-dependency.sh github.com/kcp-dev/apimachinery/v2 rebase-staging
GOWORK= ./hack/pin-dependency.sh github.com/kcp-dev/client-go rebase-staging
git add . && git commit -m 'CARRY: <drop>: Add kcp dependencies'
```

Update the vendor directories:

```bash
GOWORK= ./hack/update-vendor.sh
git add . && git commit -m 'CARRY: <drop>: vendor'
```

And run the code generator:

```bash
GOWORK= ./hack/update-codegen.sh
git add . && git commit -m 'CARRY: <drop>: codegen'
```

During the vendoring go likes to replace the `v0` tags of the kubernetes
deps - that however breaks when kcp then tries to import the kube fork.
To prevent this replace all the changed versions:

```bash
../hack/kube-repin-staging.bash
git add . && git commit -m 'CARRY: <drop>: fix v0 tags'
```

This can't happen beforehand though as resetting the tags then breaks
code generation.

And then push this to your fork and create a PR in kcp-dev/kubernetes.

### kcp-dev/kcp

While the kcp-dev/kubernetes PR is up go ahead and update the kcp branch
to use the updated kubernetes fork:

```bash
cd kcp/
GITHUB_USER=<user> GITHUB_REPO=kubernetes BRANCH=<your branch> ./hack/bump-k8s.sh
```

And bump the `k8s.io/kubernetes` line in the `go.mod` to the new version.

<!-- TODO(ntnn): Could include this in bump-k8s.sh by accepting a KUBE_VERSION env var or similar -->

If that fails upstream probably added a new staging repository. Compare
the replacements in the go.mod with the directories in the staging dir.

After the kcp-dev/kubernetes PR was merged update the kcp-dev/kcp PR to
point to the new branch:

```bash
cd kcp/
GITHUB_USER=kcp-dev GITHUB_REPO=kubernetes BRANCH=kcp-$NEW_KUBE_TAG BUMP_STAGING_MODULES=true ./hack/bump-k8s.sh
```

Then the PR in kcp-dev/kcp can be merged.

## Re-exporting patches after conflict resolution

Once all patches apply cleanly on the new base tag, re-export them to update
the patch files based on your local branch.

```bash
./hack/format-kube-patches.bash "$NEW_KUBE_1_TAG" "kcp-$NEW_KUBE_1_TAG"
./hack/null-kube-patch-hashes.bash
```

Commit the updated patches in this repository.
