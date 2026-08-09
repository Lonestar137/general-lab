import dagger
from dagger import dag, function, object_type


@object_type
class DaggerCicd:
    @function
    def container_echo(self, string_arg: str) -> dagger.Container:
        """Returns a container that echoes whatever string argument is provided"""
        return dag.container().from_("alpine:latest").with_exec(["echo", string_arg])

    @function
    async def grep_dir(self, directory_arg: dagger.Directory, pattern: str) -> str:
        """Returns lines that match a pattern in the files of the provided Directory"""
        return await (
            dag.container()
            .from_("alpine:latest")
            .with_mounted_directory("/mnt", directory_arg)
            .with_workdir("/mnt")
            .with_exec(["grep", "-R", pattern, "."])
            .stdout()
        )

    @function
    async def build_wheelhouse(
        self, directory_arg: dagger.Directory
    ) -> dagger.Container:
        """Build the wheelhouse"""
        return await (
            dag.container()
            .from_("python:3.14-slim")
            .with_mounted_directory("/app", directory_arg)
            .with_workdir("/app")
            .with_exec(["pip", "wheel", "-w", "wheelhouse", "."])
            .with_workdir("./wheelhouse")
            .with_exec(["pip", "download", "-d", ".", "../"])
        )
