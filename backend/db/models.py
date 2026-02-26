from sqlalchemy import Column, String, Integer, JSON, ForeignKey, DateTime, Text, UniqueConstraint
from sqlalchemy.orm import declarative_base, relationship
from datetime import datetime, timezone
import uuid

Base = declarative_base()

def _uuid():
    return str(uuid.uuid4())

# ─── Auth ─────────────────────────────────────────────────────────────────────
class User(Base):
    __tablename__ = 'users'

    id = Column(String, primary_key=True, default=_uuid)
    email = Column(String, nullable=False, unique=True, index=True)
    hashed_password = Column(String, nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    projects = relationship('Project', back_populates='user', cascade='all, delete-orphan')

# ─── Projects ─────────────────────────────────────────────────────────────────
class Project(Base):
    __tablename__ = 'projects'

    id = Column(String, primary_key=True, default=_uuid)
    name = Column(String, nullable=False)
    description = Column(Text, nullable=True)
    user_id = Column(String, ForeignKey('users.id'), nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    user = relationship('User', back_populates='projects')
    scenes = relationship('Scene', back_populates='project', cascade='all, delete-orphan',
                          order_by='Scene.sequence_index')

# ─── Scenes ───────────────────────────────────────────────────────────────────
class Scene(Base):
    __tablename__ = 'scenes'
    __table_args__ = (
        UniqueConstraint('project_id', 'sequence_index', name='uq_project_seq'),
    )

    id = Column(String, primary_key=True, default=_uuid)
    project_id = Column(String, ForeignKey('projects.id'), nullable=False, index=True)
    sequence_index = Column(Integer, nullable=False)
    prompt = Column(Text, nullable=False)
    scene_text = Column(Text, nullable=False)
    critic_report = Column(JSON, nullable=True)
    location = Column(String, nullable=True)
    participants = Column(JSON, nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    project = relationship('Project', back_populates='scenes')

# ─── Legacy Narrative State (kept for orchestrator compat) ────────────────────
class Character(Base):
    __tablename__ = 'characters'

    id = Column(String, primary_key=True)
    name = Column(String, nullable=False)
    core_psychology = Column(String, nullable=False)
    current_state = Column(JSON, nullable=False)

class WorldRule(Base):
    __tablename__ = 'world_rules'

    id = Column(String, primary_key=True)
    category = Column(String, nullable=False)
    rule_text = Column(String, nullable=False)
    active_scope = Column(String, nullable=False)

class TimelineEvent(Base):
    __tablename__ = 'timeline_events'

    id = Column(String, primary_key=True)
    project_id = Column(String, ForeignKey('projects.id'), nullable=True, index=True)
    sequence_index = Column(Integer, nullable=False)
    location = Column(String, nullable=False)
    participants = Column(JSON, nullable=False)
    summary = Column(String, nullable=False)
    causal_prerequisites = Column(JSON, nullable=True)

def init_db(engine):
    Base.metadata.create_all(engine)
