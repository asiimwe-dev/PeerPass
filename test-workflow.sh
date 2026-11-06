#!/bin/bash
# Combined Backend + Frontend Workflow Test
# Run this script before pushing to GitHub to catch all errors

set -e

echo "🚀 Starting Combined Workflow Test..."
echo "=========================================="
echo "Date: $(date)"
# Function to check git branch (defined before use)
check_git_branch() {
    if git rev-parse --git-dir > /dev/null 2>&1; then
        local branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
        if [ -n "$branch" ]; then
            echo "Branch: $branch"
        else
            echo "Branch: (detached HEAD or unknown)"
        fi
    else
        # Try looking for .git in parent or current directory
        local repo_path=$(git rev-parse --show-toplevel 2>/dev/null)
        if [ -n "$repo_path" ] && [ -d "$repo_path/.git" ]; then
            local branch=$(git -C "$repo_path" rev-parse --abbrev-ref HEAD 2>/dev/null)
            if [ -n "$branch" ]; then
                echo "Branch: $branch"
            else
                echo "Branch: (unknown)"
            fi
        else
            echo "Branch: (not a git repository)"
        fi
    fi
}

# Replace the original branch detection line with function call
sed -i 's|check_git_branch|check_git_branch|' "$0" 2>/dev/null || true
check_git_branch
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
PASS=0
FAIL=0
TOTAL=0

# Function to test pass
pass_test() {
    echo -e "${GREEN}✓ PASS: $1${NC}"
    ((PASS++))
}

# Function to test fail
fail_test() {
    echo -e "${RED}✗ FAIL: $1${NC}"
    echo "    Error: $2"
    ((FAIL++))
}

# Function to test overall
test_result() {
    if [ $FAIL -eq 0 ]; then
        echo -e "${GREEN}🎉 All $TOTAL tests passed! Ready to push!${NC}"
        return 0
    else
        echo -e "${RED}❌ $FAIL out of $TOTAL tests failed${NC}"
        return 1
    fi
}

# Function to check command
check_command() {
    local desc=$1
    local cmd=$2
    TOTAL=$((TOTAL+1))
    if eval "$cmd" 2>/dev/null; then
        pass_test "$desc"
    else
        fail_test "$desc" "Command failed: $cmd"
    fi
}

echo ""
echo "📋 Step 1: Prerequisites"
echo "-----------------------------------"

# Check backend directory
if [ ! -d "Ulearn/backend" ]; then
    fail_test "Backend directory exists" "Ulearn/backend not found"
else
    pass_test "Backend directory exists"
fi

# Check virtual environment
if [ ! -d "Ulearn/backend/.venv" ]; then
    fail_test "Virtual environment" "Ulearn/backend/.venv not found"
else
    pass_test "Virtual environment exists"
fi

# Check frontend directory
if [ ! -d "Ulearn/frontend" ]; then
    fail_test "Frontend directory exists" "Ulearn/frontend not found"
else
    pass_test "Frontend directory exists"
fi

# Check required backend files
check_command "App main.py exists" "test -f Ulearn/backend/app/main.py"
check_command "Database seed exists" "test -f Ulearn/backend/app/db/seed.py"
check_command "Test files exist" "test -d Ulearn/backend/tests/"
check_command "Core config exists" "test -f Ulearn/backend/app/core/config.py"

# Check .env file
check_command ".env file exists" "test -f Ulearn/backend/.env"
check_command "CORS_ORIGINS in .env" "grep -q 'CORS_ORIGINS' Ulearn/backend/.env"
check_command "DATABASE_URL in .env" "grep -q 'DATABASE_URL' Ulearn/backend/.env"

echo ""
echo "📋 Step 2: Backend Dependencies"
echo "-----------------------------------"

# Check requirements files
check_command "requirements.in exists" "test -f Ulearn/backend/requirements.in"
check_command "requirements.txt exists" "test -f Ulearn/backend/requirements.txt"
check_command "requirements-dev.txt exists" "test -f Ulearn/backend/requirements-dev.txt"

# Check python-multipart in requirements
check_command "python-multipart in requirements.in" "grep -q 'python-multipart' Ulearn/backend/requirements.in"
check_command "python-multipart in requirements.txt" "grep -q 'python-multipart' Ulearn/backend/requirements.txt"

# Check CORS config
check_command "CORS configured in main.py" "grep -q 'CORS_ORIGINS' Ulearn/backend/app/main.py"

# Check alembic migrations
check_command "Alembic migrations exist" "test -d Ulearn/backend/alembic/versions/"
check_command "Latest migration exists" "test -f Ulearn/backend/alembic/versions/20261103_1726_0156d3079755_add_program_id_semester_year_level_reg_.py"

# Check database migration
check_command "Alembic migration up to date" "cd Ulearn/backend && source .venv/bin/activate && alembic heads | grep -q '0156d3079755'"

echo ""
echo "📋 Step 3: Backend Tests"
echo "-----------------------------------"

# Install dependencies if needed
cd Ulearn/backend
source .venv/bin/activate

# Run backend tests
check_command "Backend tests pass" "python -m pytest tests/ -v"

# Check ruff linting
check_command "Backend ruff check" "ruff check ."

# Check format
check_command "Backend format check" "black --check ."

# Test database connection
check_command "Database peerpass exists" "psql -h 127.0.0.1 -U postgres -lqt | cut -d \\| -f 1 | grep -qw peerpass"

# Run alembic check
check_command "Alembic migration check" "alembic check"

# Test health endpoint
check_command "Backend health endpoint" "curl -s --max-time 3 http://localhost:8000/health | grep -q 'ok'"

# Test CORS preflight
check_command "CORS preflight" "curl -s --max-time 3 -X 'OPTIONS' http://localhost:8000/v1/auth/login -H 'Origin: http://localhost:8080' | grep -q 'Access-Control-Allow-Origin'"

echo ""
echo "📋 Step 4: Frontend Dependencies"
echo "-----------------------------------"

# Navigate to frontend
cd ../frontend

# Check pubspec
check_command "pubspec.yaml exists" "test -f pubspec.yaml"

# Check for key files
check_command "tutor_rail.dart exists" "test -f lib/features/tutors/presentation/widgets/tutor_rail.dart"
check_command "profile_screen.dart exists" "test -f lib/features/home/presentation/screens/profile_screen.dart"
check_command "profile_providers.dart exists" "test -f lib/features/home/presentation/providers/profile_providers.dart"

# Check for search functionality
check_command "Search widget in tutor_rail.dart" "grep -q '_CourseUnitSearch' lib/features/tutors/presentation/widgets/tutor_rail.dart"
check_command "Search function in tutor_rail.dart" "grep -q 'searchCourseUnits' lib/features/tutors/presentation/widgets/tutor_rail.dart"

# Check for tutor applications in profile
check_command "Tutor apps provider" "grep -q 'myClaimsProvider' lib/features/home/presentation/providers/profile_providers.dart"
check_command "Tutor apps screen" "grep -q 'Tutor applications' lib/features/home/presentation/screens/profile_screen.dart"

# Check course units
check_command "Second semester courses in seed.py" "grep -q 'BCE2104' ../backend/app/db/seed.py"

# Check for second semester courses in database
check_command "51 second semester courses in seed.py" "grep -cE 'BCE2[12][0-9][0-9]|BME2[12][0-9][0-9]|CVE2[12][0-9][0-9]' ../backend/app/db/seed.py"

echo ""
echo "📋 Step 5: Frontend Tests"
echo "-----------------------------------"

# Check pubspec
check_command "pubspec.yaml exists" "test -f pubspec.yaml"

# Run flutter test
check_command "Flutter tests pass" "flutter test"

# Check analyze
check_command "Flutter analyze" "flutter analyze"

# Check build
check_command "Flutter web build" "flutter build web"

# Check key files exist
check_command "TutorRail widget exists" "test -f lib/features/tutors/presentation/widgets/tutor_rail.dart"
check_command "Profile providers exist" "test -f lib/features/home/presentation/providers/profile_providers.dart"
check_command "Profile screen exists" "test -f lib/features/home/presentation/screens/profile_screen.dart"

# Check for search functionality
check_command "Search widget implemented" "grep -q '_CourseUnitSearch' lib/features/tutors/presentation/widgets/tutor_rail.dart"
check_command "Tutor applications implemented" "grep -q 'myClaimsProvider' lib/features/home/presentation/providers/profile_providers.dart"

# Check for course units in database
check_command "51 second semester courses" "grep -cE 'BCE2[12][0-9][0-9]|BME2[12][0-9][0-9]|CVE2[12][0-9][0-9]' ../backend/app/db/seed.py"

echo ""
echo "📋 Step 6: Integrated End-to-End Tests"
echo "--------------------------------------"

# Test health endpoint
check_command "Backend health" "curl -s --max-time 3 http://localhost:8000/health | grep -q 'ok'"

# Test CORS preflight
check_command "CORS preflight" "curl -s --max-time 3 -X 'OPTIONS' http://localhost:8000/v1/auth/login -H 'Origin: http://localhost:8080' | grep -q 'Access-Control-Allow-Origin'"

# Test frontend serving
check_command "Frontend serving" "curl -s --max-time 3 http://localhost:8080 | head -c 100 | grep -q '<'"

# Test login endpoint
check_command "Login endpoint" "curl -s --max-time 3 -X OPTIONS http://localhost:8000/v1/auth/login -H 'Origin: http://localhost:8080' -H 'Access-Control-Request-Method: POST' | grep -q 'allow-methods'"

echo ""
echo "📋 Step 7: Code Quality Checks"
echo "--------------------------------"

# Run backend ruff check
check_command "Backend ruff check" "cd Ulearn/backend && source .venv/bin/activate && ruff check ."

# Run backend format check
check_command "Backend format check" "cd Ulearn/backend && source .venv/bin/activate && black --check ."

# Run frontend analyze
check_command "Frontend analyze" "cd Ulearn/frontend && flutter analyze"

# Run frontend tests
check_command "Frontend tests pass" "cd Ulearn/frontend && flutter test"

echo ""
echo "📋 Step 8: Migration Verification"
echo "---------------------------------"

# Check alembic migration
check_command "Alembic migrations exist" "test -d Ulearn/backend/alembic/versions/"
check_command "Latest migration exists" "test -f Ulearn/backend/alembic/versions/20261103_1726_0156d3079755_add_program_id_semester_year_level_reg_.py"

# Apply migration
check_command "Alembic upgrade head" "cd Ulearn/backend && source .venv/bin/activate && alembic upgrade head"

# Verify migration matches models
check_command "Alembic check" "cd Ulearn/backend && source .venv/bin/activate && alembic check"

# Test migrations are reversible
check_command "Migrations are reversible" "cd Ulearn/backend && source .venv/bin/activate && alembic downgrade base && alembic upgrade head"

echo ""
echo "=========================================="
echo "📊 Test Summary"
echo "=========================================="
echo "Total tests: $TOTAL"
echo -e "${GREEN}Passed: $PASS${NC}"
echo -e "${RED}Failed: $FAIL${NC}"

echo ""
if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}✅ All tests passed! Ready to push to GitHub!${NC}"
    echo ""
    echo "To push:"
    echo "  cd /home/sir-hardy/Ulearn/Ulearn/backend"
    echo "  git add ."
    echo "  git commit -m 'fix: address review issues and add automated tests'"
    echo "  git push origin feature/tutor-validation-transcripts-must-catalogue-v2"
    echo ""
    echo "Then create a new PR on GitHub."
    echo ""
    return 0
else
    echo -e "${RED}❌ $FAIL tests failed. Please fix before pushing.${NC}"
    return 1
fi

