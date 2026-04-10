FROM node:lts-alpine
WORKDIR /work
RUN npm install -g zenn-cli
CMD ["npx", "zenn", "preview"]
