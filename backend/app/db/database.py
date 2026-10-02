from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

# The database connection string
SQLALCHEMY_DATABASE_URL = "postgresql+psycopg://postgres:YourNewPassword123!@localhost:5432/ulearn"

engine = create_engine(SQLALCHEMY_DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

# Dependency to open and close the database session securely
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()