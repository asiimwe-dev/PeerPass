from fastapi import FastAPI, Depends, HTTPException
from sqlalchemy import create_engine, Column, String, Integer, Boolean, Enum as SQLEnum
from sqlalchemy.orm import sessionmaker, Session, declarative_base
from sqlalchemy.dialects.postgresql import UUID
from pydantic import BaseModel
import uuid

# ==========================================
# 1. DATABASE CONFIGURATION
# ==========================================
# Replaced psycopg2 with psycopg to match your requirements.txt
SQLALCHEMY_DATABASE_URL = "postgresql+psycopg://postgres:YourNewPassword123!@localhost:5432/ulearn"

engine = create_engine(SQLALCHEMY_DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

# ==========================================
# 2. SQLALCHEMY MODEL
# ==========================================
class User(Base):
    __tablename__ = "users"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String, nullable=False)
    email = Column(String, unique=True, index=True, nullable=False)
    password_hash = Column(String, nullable=False)
    faculty = Column(String, nullable=False)
    year_of_study = Column(Integer, nullable=False)
    tutor_status = Column(SQLEnum('None', 'Provisional', 'Verified', name='tutor_status_enum'), default='None')
    is_admin = Column(Boolean, default=False)

# ==========================================
# 3. PYDANTIC SCHEMAS
# ==========================================
class UserCreate(BaseModel):
    name: str
    email: str
    password: str 
    faculty: str
    year_of_study: int

class UserLogin(BaseModel):
    email: str
    password: str

# ==========================================
# 4. FASTAPI APP & ROUTES
# ==========================================
app = FastAPI()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

@app.post("/api/users/")
def create_user(user: UserCreate, db: Session = Depends(get_db)):
    existing_user = db.query(User).filter(User.email == user.email).first()
    if existing_user:
        raise HTTPException(status_code=400, detail="Email already registered")

    db_user = User(
        name=user.name,
        email=user.email,
        password_hash=user.password, 
        faculty=user.faculty,
        year_of_study=user.year_of_study
    )
    
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    
    return {"message": "User created successfully", "user_id": db_user.id}

@app.post("/api/login/")
def login_user(user: UserLogin, db: Session = Depends(get_db)):
    db_user = db.query(User).filter(User.email == user.email).first()
    
    if not db_user:
        raise HTTPException(status_code=404, detail="User not found")
        
    if db_user.password_hash != user.password:
        raise HTTPException(status_code=401, detail="Incorrect password")
        
    return {
        "message": "Login successful", 
        "user_id": db_user.id,
        "name": db_user.name,
        "tutor_status": db_user.tutor_status
    }
