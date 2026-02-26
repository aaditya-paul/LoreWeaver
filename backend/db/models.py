from sqlalchemy import Column, String, Integer, JSON, ForeignKey
from sqlalchemy.orm import declarative_base, relationship
from sqlalchemy.ext.declarative import declarative_base

Base = declarative_base()

class Character(Base):
    __tablename__ = 'characters'
    
    id = Column(String, primary_key=True)
    name = Column(String, nullable=False)
    core_psychology = Column(String, nullable=False) # Immutable traits
    current_state = Column(JSON, nullable=False) # Mutable state dict
    
    # Optional relationships to other characters could be added via adjacency list or relationship table

class WorldRule(Base):
    __tablename__ = 'world_rules'
    
    id = Column(String, primary_key=True)
    category = Column(String, nullable=False)
    rule_text = Column(String, nullable=False)
    active_scope = Column(String, nullable=False)

class TimelineEvent(Base):
    __tablename__ = 'timeline_events'
    
    id = Column(String, primary_key=True)
    sequence_index = Column(Integer, nullable=False, unique=True)
    location = Column(String, nullable=False)
    participants = Column(JSON, nullable=False) # List of character IDs
    summary = Column(String, nullable=False)
    causal_prerequisites = Column(JSON, nullable=True) # List of event IDs

def init_db(engine):
    Base.metadata.create_all(engine)
