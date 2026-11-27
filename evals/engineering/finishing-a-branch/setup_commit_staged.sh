. "$(dirname "$0")/_git_setup.sh"
sed -i 's/Hello, /Hi, /' app/greeting.py
git add app/greeting.py
note origin_main "$(git rev-parse origin/main)"
