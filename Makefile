all:
	cd themes/geekblog && npm install && npm run build
	hugo
