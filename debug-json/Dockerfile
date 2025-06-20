FROM alpine:3.20
RUN apk add --no-cache jq
CMD ["sh", "-c", "echo \"RAW BOT_CONFIG: '$BOT_CONFIG'\" && echo \"$BOT_CONFIG\" | jq -e . && echo \"Meeting URL:\" && echo \"$BOT_CONFIG\" | jq -r '.meetingUrl' && echo \"✓ JSON parsed\""] 