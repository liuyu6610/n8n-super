param(
  [string]$Tag = "n8n-super:1.78.1"
)

docker build -t $Tag .
