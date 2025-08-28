# PGXN Submission Guide for pgcalendar

This document provides step-by-step instructions for submitting the pgcalendar extension to the PostgreSQL Extension Network (PGXN).

## What We've Created

Your extension is now properly structured for PGXN publication with the following files:

### Core Extension Files

- `pgcalendar.control` - Extension control file
- `pgcalendar--1.0.0.sql` - Main installation script
- `pgcalendar--1.0.0--uninstall.sql` - Uninstallation script

### Documentation

- `README.md` - Comprehensive user documentation
- `INSTALL.md` - Installation guide
- `LICENSE` - PostgreSQL License

### Testing

- `test/sql/pgcalendar_test.sql` - Test suite
- `test/expected/pgcalendar_test.out` - Expected test results
- `test/run_tests.sh` - Test runner script

### Build System

- `Makefile.pgxn` - PGXN-compatible Makefile
- `META.json` - Extension metadata for PGXN

## PGXN Submission Steps

### Step 1: Create PGXN Account

1. Go to [PGXN.org](https://pgxn.org/)
2. Click "Sign Up" and create an account
3. Verify your email address

### Step 2: Prepare Your Extension

Your extension is already prepared! The `pgcalendar-1.0.0.tar.gz` file contains everything needed.

### Step 3: Submit to PGXN

1. Log in to your PGXN account
2. Go to "Submit Extension"
3. Upload the `pgcalendar-1.0.0.tar.gz` file
4. Fill in the submission form:
   - **Name**: pgcalendar
   - **Abstract**: Infinite Calendar Extension for PostgreSQL with recurring events, schedules, and exception handling
   - **Description**: Use the description from META.json
   - **License**: MIT License
   - **Tags**: calendar, recurring, events, scheduling, projections, exceptions
   - **Homepage**: Your GitHub repository URL
   - **Repository**: Your GitHub repository URL

### Step 4: Wait for Review

PGXN moderators will review your submission. This usually takes 1-3 business days.

## What Happens After Submission

### If Approved

- Your extension will be available on PGXN
- Users can install it with `pgxn install pgcalendar`
- You'll receive a confirmation email

### If Rejected

- You'll receive feedback on what needs to be fixed
- Make the necessary changes and resubmit

## Post-Submission Tasks

### 1. Update Your Repository

After successful submission, update your GitHub repository:

```bash
# Add the new files
git add .
git commit -m "Prepare extension for PGXN publication"
git push origin master

# Create a release tag
git tag -a v1.0.0 -m "Version 1.0.0 - PGXN release"
git push origin v1.0.0
```

### 2. Update Documentation

Add PGXN installation instructions to your README:

````markdown
## Installation

### From PGXN (Recommended)

```bash
pgxn install pgcalendar
```
````

### From Source

[existing instructions...]

````

### 3. Monitor and Maintain

- Monitor PGXN for user feedback
- Respond to issues and questions
- Plan future releases

## Testing Your Extension

Before submitting, test your extension thoroughly:

### 1. Test Installation
```bash
# Test the PGXN package
tar -xzf pgcalendar-1.0.0.tar.gz
cd pgcalendar-1.0.0
make
sudo make install
````

### 2. Test in Database

```sql
CREATE EXTENSION pgcalendar;
SELECT * FROM pgcalendar.event_calendar LIMIT 5;
```

### 3. Run Test Suite

```bash
cd test
./run_tests.sh
```

## Common Issues and Solutions

### 1. Extension Not Found

- Ensure all files are in the correct locations
- Check file permissions
- Verify PostgreSQL version compatibility

### 2. Test Failures

- Review test output for specific errors
- Check database state
- Verify function implementations

### 3. Build Errors

- Ensure PostgreSQL development tools are installed
- Check Makefile syntax
- Verify file paths

## Version Management

For future releases:

1. Update version numbers in all files:

   - `pgcalendar.control`
   - `META.json`
   - SQL file names
   - Documentation

2. Create new SQL files:

   - `pgcalendar--1.0.1.sql` (upgrade script)
   - `pgcalendar--1.0.0--1.0.1.sql` (downgrade script)

3. Update the package:
   - Recreate the tar.gz file
   - Submit to PGXN

## Support and Community

### PGXN Resources

- [PGXN Documentation](https://pgxn.org/docs/)
- [PGXN Mailing List](https://groups.google.com/forum/#!forum/pgxn-users)
- [PGXN IRC Channel](irc://irc.freenode.net/#pgxn)

### PostgreSQL Resources

- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [PostgreSQL Extensions](https://www.postgresql.org/docs/current/extend.html)
- [PostgreSQL Mailing Lists](https://www.postgresql.org/community/lists/)

## Final Checklist

Before submitting to PGXN, ensure:

- [ ] All required files are present
- [ ] Extension builds and installs correctly
- [ ] Tests pass successfully
- [ ] Documentation is complete and accurate
- [ ] License is properly specified
- [ ] META.json contains all required fields
- [ ] Package structure follows PGXN standards
- [ ] Extension works with supported PostgreSQL versions

## Congratulations!

You're now ready to submit your pgcalendar extension to PGXN! This will make it available to the entire PostgreSQL community and allow users to easily install and use your extension.

Good luck with your submission!
