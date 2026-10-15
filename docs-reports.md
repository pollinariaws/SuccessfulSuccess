# Weekly report: answers

## 1. The same ObjectCreated event twice, two identical emails

Store a "sent" record in DynamoDB, written with a conditional put
(attribute_not_exists) before sending. Key: report key + S3 object version id
(or ETag) + recipient, e.g. `reports/2026-W40.csv#<etag>#<recipient>`. A retry
carries the same event and ETag, so the second write fails and the mailer skips
the send. A rebuilt report has a new ETag, so a deliberate rebuild still goes
out. Set a TTL so old rows disappear. Note the ordering problem: record first,
send second, and a crash in between loses the email, while send first, record
second can duplicate it. At-least-once delivery means you pick which risk to keep.

## 2. The builder in the VPC cannot reach SES

- NAT gateway: works for everything, but billed hourly plus per GB, roughly
  $33 a month in the lab's region. Always on.
- VPC interface endpoint for SES: private path, billed hourly per availability
  zone (about $7 a month each, so roughly $22 with three zones) plus data.
- The split built here: a second Lambda outside the VPC. Costs nothing fixed;
  you pay per invocation, which stays inside the free tier at this volume.

With ten more emails a week I keep the split: any fixed monthly fee is far more
than the whole workload. With a million emails a week SES itself dominates the
bill, and the split is still cheaper than a fixed NAT, but the extra hop and the
second function become something to maintain, so a shared endpoint or a single
function would be worth comparing at that point.

## 3. A link that works for a week

A presigned URL signed with a Lambda role's temporary credentials dies when those
credentials expire. Options: put a link in the email to an endpoint of the app
that checks who is asking and then generates a fresh presigned URL on click; or
use CloudFront signed URLs with a key pair, where the expiry is chosen
explicitly and does not depend on role credentials.