#!/bin/bash
if [[ -f "./hugo" ]]; then
	./hugo
else
	hugo
fi

chmod -R ug+rwX public/
rsync -avuz --chown=ad-blog:ad-blog public/ root@topi.informatik.privat:/var/www/ad-blog/
