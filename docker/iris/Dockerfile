ARG IRIS_IMAGE=containers.intersystems.com/intersystems/iris-community:latest-cd
FROM ${IRIS_IMAGE}

COPY --chown=irisowner:irisowner src /opt/jvdoc/src
COPY --chown=irisowner:irisowner docker/iris/Installer.cls /opt/jvdoc/docker/Installer.cls

# Build the demo environment once, at image build time; a failing step fails the build
RUN iris start IRIS \
 && printf '%s\n' \
      'Set sc = $System.OBJ.Load("/opt/jvdoc/docker/Installer.cls", "ck")' \
      'If $System.Status.IsOK(sc) Set sc = ##class(JVDocDemo.Installer).Run()' \
      'If $System.Status.IsOK(sc) Write !,"JVDoc demo installed",!' \
      'If $System.Status.IsError(sc) Do $System.Status.DisplayError(sc) Do $System.Process.Terminate(, 1)' \
      'Halt' \
    | iris session IRIS -U %SYS \
 && iris stop IRIS quietly
