# Seeding is now done via the UI.
#
# 1. Log in to the app
# 2. Click "Seed your data!" button in the sidebar
#
# This uses SocialScribe.Seeds.run/1 which creates demo meetings
# with transcripts for the logged-in user.
#
# For programmatic seeding (e.g., in tests or console):
#
#     user = SocialScribe.Accounts.get_user_by_email("your@email.com")
#     SocialScribe.Seeds.run(user)
#
