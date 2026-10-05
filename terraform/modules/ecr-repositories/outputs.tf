output "repository_urls" {
  description = "Map of full repository name (namespace/path included, if ecr_namespaces is in use) to its repository_url — e.g. { \"dev/ts-admin-tickets\" = \"123456789012.dkr.ecr.us-east-1.amazonaws.com/dev/ts-admin-tickets\" }. This is what each app-repo's own GitHub Action reads: look up your own full repo name's key, get the URL to `docker push` to — no parsing or guessing the URL shape."
  value       = { for name, mod in module.ecr : name => mod.repository_url }
}

output "repository_arns" {
  description = "Map of full repository name to its ARN, same keying as repository_urls."
  value       = { for name, mod in module.ecr : name => mod.repository_arn }
}
