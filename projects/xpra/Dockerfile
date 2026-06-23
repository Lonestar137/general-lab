FROM ubuntu:24.04

RUN apt-get update && apt-get install -y curl gnupg && \
   curl -fsSL https://xpra.org/gpg.asc | gpg --dearmor -o /usr/share/keyrings/xpra.gpg && \
   echo "deb [signed-by=/usr/share/keyrings/xpra.gpg] https://xpra.org/dists noble main" \
     > /etc/apt/sources.list.d/xpra.list && \
   apt-get update && \
   apt-get install -y xpra xpra-x11 xpra-client xpra-server && \
   rm -rf /var/lib/apt/lists/*
RUN apt update && apt install -y gitk xterm qmlscene

EXPOSE 14500

# ===Examples===
# Baking an app into the session
# CMD ["xpra", "start", "--bind-tcp=0.0.0.0:14500", "--html=on", "--daemon=no", "--start=qmlscene", "--start=xterm"]

# Adhoc commands available via:
# xpra control tcp://10.x.x.x:14500 start gitk
# xpra attach tcp://10.x.x.x:14500
CMD ["xpra", "start", "--bind-tcp=0.0.0.0:14500", "--html=on", "--daemon=no", "--start-child=xterm", "--exit-with-children=no"]

# for security use ssh, drop tcp and attach via:
# xpra attach ssh://youruser@10.x.x.x:22/
# CMD ["xpra", "start", "--html=on", "--daemon=no", "--start-child=xterm", "--exit-with-children=no"]

