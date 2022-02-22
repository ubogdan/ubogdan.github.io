
# alt template https://themes.gohugo.io/hugo-dpsg/

.PHONY: new
new:
	hugo new $(word 2, $(MAKECMDGOALS) )

.PHONY: dev
dev:
	hugo server

.PHONY: publish
publish:
	hugo
	aws s3 sync public/ s3://ubogdan.com --delete
	aws cloudfront create-invalidation --distribution-id E36TAK5X2X8KES --paths "/*"

# Styles: https://xyproto.github.io/splash/docs/all.html
gen-highlight:
	mdir -p static/css/
	hugo gen chromastyles --style=dracula > static/css/highlight.css


